# The pod connection model — how it works, what we built, what bit us

Supersedes `POD_RADIO_BEHAVIOR.md` and `POD_ENACT_DIAGNOSIS.md` (both folded in here).
Written 2026-08-21, after the first clean overnight: **36 of 36 cycles enacted, phone off,
five hours, zero failures.**

Everything numeric below is measured, most of it by a passive Mac BLE observer
(`ops/g7watch-mac`) that only ever scans and never connects — so it cannot be the thing it
is measuring.

---

# PART 1 — How the pod actually works

## 1.1 The advertisement carries the pod's identity in the clear

A DASH pod advertises **nine 16-bit service UUIDs**, and they are not services — they are a
payload smuggled into the UUID list:

```
svc = 4024, C005, 000A, 177E, 6B7E, 0856, 2FA1, 0033, 457F
       │           │     └──┬──┘   └──────┬──────┘
       │           │        │             └── lot number + sequence number
       │           │        └── pod ID = 0x177E6B7E
       │           └── fixed marker
       └── "I am an Omnipod"
```

`PodAdvertisement` decodes `serviceUUIDs[3] + [4]` as the pod ID. An **unpaired** pod
advertises `FFFF, FFFE` there — the "not activated" sentinel — so the advert also announces
availability. This is what makes a loan possible at all: a watch can recognise a pod it has
never met.

## 1.2 Pairing is not Bluetooth pairing

There is **no BLE bond**. At activation `DashLTKExchanger` runs an X25519 exchange over a
text-keyed protocol (`SP1=`, `SP2=`, `SPS1=`…) producing an **LTK**. The pod stores it against
a **controller ID** — which is just `arc4random()` with a type marker in the top byte, not
derived from the device, the bundle, or any hardware identifier. Pod IDs are then that base
plus a small counter.

So "this pod is paired to my phone" means exactly: *my phone holds that pod's LTK, and the pod
remembers that controller ID.* Four copyable values — controller ID, pod ID, LTK, EAP
sequence number — and **anything holding them IS the controller.** The pod cannot tell devices
apart. That is why the loan works without re-pairing, and why exclusivity has to be enforced by
*bookkeeping* (the monotonic `eapSqn`) rather than by identity.

## 1.3 Every connection re-authenticates with cellular crypto

Connect → service `1A7E4024-…`, two characteristics: command (`…2441`) and data (`…2442`).
Then `SessionEstablisher` runs **EAP-AKA using Milenage** — the same challenge/response a SIM
uses against a cell network — with the LTK as shared secret. Only then can a dose be sent.

Cost, measured: **connect ~1.3 s** (n=4, and 0.53 s in the overnight run); **EAP-AKA + first
status read ~4 s**. That second number is irreducible and dominates a takeover.

## 1.4 Identity is copyable; ADDRESSABILITY is not

To call `connect()` you need a `CBPeripheral`, and CoreBluetooth mints those **per device**.
Apple hides the pod's real BLE address, so the phone's `bleIdentifier` is meaningless on the
watch — same pod, different local name.

**That is the entire purpose of the takeover scan: name resolution, not authentication.** It
translates a pod ID we already know into a handle this device can use. It is needed exactly
once per (device, pod).

## 1.5 A connected pod is an invisible pod

BLE peripherals stop advertising while connected, and the pod holds one connection at a time.
So **"the pod isn't advertising" and "someone else has it" are the same observation** — every
silence longer than the measurement floor is somebody's connection window.

## 1.6 The pod's natural rhythm

Clean room (loan ended, both apps quit, both radios off, one hour, close range):

```
  0-2s   43.9%      10-30s   1.8%
  2-5s    8.4%      30-60s   0.0%
 5-10s   45.7%     60-300s   0.2%   (two events: 258s, 182s)
```

**98% of gaps are under 10 seconds.** Quiet spells exist — two an hour, longest 258 s, 10.9%
of wall-clock — but they are the exception, not the rule.

## 1.7 Delivery does NOT require a connection

| bolus | delivery time (~0.05 U/s) | observed hold |
|---|---|---|
| 0.10 U | ~2 s | none — gaps 5-11 s, indistinguishable from idle |
| **2.8 U** | **~56 s** | **none — pod advertising throughout** |

Delivery confirmed audibly (the pod clicks) while it kept advertising every 5-6 s. Loop
commands the bolus, drops the link, and the pod delivers autonomously; completion arrives on a
later status read.

**So never design a "hold the pod through delivery" policy.** `estimatedDuration(toBolus:)`
exists but its only consumer is `DeviceDataManager` bookkeeping — nothing in the BLE layer uses
it, and hold time does not scale with bolus size at all.

## 1.8 The pod hangs up on an idle held link

`Code=7`, peripheral-initiated, roughly every 5 s. A held link needs periodic traffic to
survive. This is the fact that decides the whole design below.

---

# PART 2 — The two connection models, and why the watch differs

## 2.1 Pure (`SportMode`) — standing connection, four lines

```swift
if autoConnectIDs.contains(peripheral.identifier.uuidString) {
    central.connect(peripheral, options: nil)     // on disconnect, reconnect. that's it.
}
```

`central.connect()` never times out, so this is a standing bid that resolves whenever the pod
is reachable. No ladder, no scan-adopt, no teardown logic. It survives §1.8 only because the
phone's keep-alive constantly polls the pod.

## 2.2 next-dev — connect-on-demand, **switched by app foreground**

```swift
var shouldHoldConnection: Bool {
    if isAppForeground { return true }     // ← the switch
    ...
}
```

Measured, closed loop, close range:

| phone state | pod held |
|---|---|
| **foreground** | 41 s, 59 s, 108 s, 244 s, 655 s windows, ~50%+ of wall-clock — effectively standing |
| **backgrounded** | **zero holds >28 s in 12 min. 0% unavailable.** |

`connectOnDemandEnabled` defaults true but **foreground silently overrides it**. Several hours
of this investigation measured the wrong mode because the app was on screen.

## 2.3 Why the watch cannot copy either one

**hold-for-loan was tested and REJECTED** (2026-08-20, `Lab.podReleaseDelay = -1`). The pod
side worked perfectly — `L4 OK after 0 read(s) — link already up` — and the G7 died in ~13
minutes with `CBError 11`.

Mechanism: per §1.8 the pod hangs up on the idle held link every ~5 s; `autoReconnect` re-bids
instantly; each cycle briefly overlaps an old teardown with a new pending connect, and G7's
2-second retries land in those windows. Never three steady connections — a race.

**So orphan-between-doses is load-bearing for two independent reasons:** it frees the second
BLE slot for G7, *and* it avoids fighting the pod's own idle-disconnect. A phone has no CGM
central competing in-process; a watch does.

*(Note: `CBError 11` is a CENTRAL-side limit — the watch's own stack. A G7 serves several
simultaneous connections; that is the founding premise of the D2W piggyback work. An earlier
draft claimed otherwise and was wrong.)*

---

# PART 3 — What we built

The watch now behaves as a **permanently-backgrounded phone**, with one deliberate exception.

1. **`shouldHoldConnection` returns false on watchOS, unconditionally.** The foreground rule is
   right for a phone and wrong here (§2.3). With it false, the driver's own **4 s
   idle-disconnect** governs release — better than the loan layer's fixed 12 s timer, because it
   resets per session so a status-read + dose burst shares one connection.

2. **A per-pod BLE handle cache** (`PodLoanBleIdentifierCache`, keyed by pod address). The watch
   already learned the right handle on adopt and then discarded it, because the pump manager is
   rebuilt from the phone's snapshot at every grant. Now it persists.

3. **Handle substitution at grant intake.** The grant's `bleIdentifier` is the phone's and
   useless here; ours goes in instead, before `OmniPumpManager` is constructed.

4. **No-scan takeover** when a handle resolves, with two fallbacks: an unrecognised handle fails
   immediately (`retrievePeripherals` returns empty) and falls through to discovery; a
   recognised-but-unreachable one is covered by a 6 s timer, because a bare `connect()` has no
   timeout and would otherwise hang forever.

5. **No escalation on reclaim when a handle is known.** On watchOS `escalateLoanReclaim` calls
   `recreateCentral()`, and that was running on *every dose cycle* (see §4.3). Gentle reconnect
   first; the ladder escalates at read 4 if it has not landed, once per ladder.

6. **A wall-clock ladder ceiling (45 s)**, because "14 reads × ~2 s" stopped being true once
   reads became honest (§4.4).

7. **Bounded hand-back drain and no repeated urgent-send timeouts** (§4.5, §4.6).

**Nothing new was needed to USE the handle.** `BlePodComms.init` already calls
`connectToDevice(uuidString:)` from `podState.bleIdentifier`, and `bleRunSession` already adopts
a `PeripheralManager` from it while disconnected, then goes through `configureAndRun →
connectOnDemand`. The lean path was always there; it had never been given a usable handle.

## Result — overnight 2026-08-21, phone off, 5 hours

```
enact=ok                   36        G7 ingests           56
enact=FAILED                0        CBError 11            0
NO escalate                56        ORPHANED PeriphMgr    0
mid-ladder escalate         0        central=nil           0
takeover scans started      0        reclaim ABANDONED     0
median gap between cycles  301s
```

---

# PART 4 — The obstacles, and how each announced itself

Kept because each has a *signature*, and recognising the signature is most of the fix.

## 4.1 We were cancelling our own connects

**Signature:** `cancelled:disconnectOnDemand`, 6 of 6, at 0.36–1.87 s against a ~1.3 s connect.

The reclaim ladder polls every ~2 s; a poll's connect command can throw FAST (`notReady`, or a
pending-conditions collision — `runCommand`'s only sub-timeout exits), and the catch "cleaned
up" by cancelling the in-flight connect, which *was* the recovery. Fixed by refusing that
teardown while the loan marker is armed.

## 4.2 An orphaned `PeripheralManager`, permanently

**Signature:** a ladder with `adverts=0 anySeen=0` and **no `[intent] connect` line at all** —
14 reads, 28 s, nothing on the radio because nothing was ever asked for.

`PeripheralManager` holds its central **weakly**. `recreateCentral()` installs a new
`CBCentralManager` and clears `devices`, so every existing PeripheralManager's `central`
silently becomes nil — and `BlePodComms` keeps a *strong* reference to one of those while
re-adopting only `if manager == nil`. Every command then threw `notReady` forever.

Only nameable because the `notReady` log line was extended to print
`central=… peripheral=… queueDepth=…`. **Instrumentation that prints the guard's own inputs
paid for itself here more than anywhere else.**

## 4.3 …and it was happening on every dose cycle

`E4: reclaiming pod to dose (scan-adopt primary)` escalated *immediately*, and on watchOS
escalation recreates the central. So every cycle orphaned the command path and cost 30–100 s to
recover. Scan-adopt was made primary because a bare connect "wins ~2%" — but that was measured
when a bare connect was a blind bid with **no local handle**. With one it is the phone's
mechanism.

## 4.4 Honest reads, dishonest budget

**Signature:** `L7 FAILED after 14 read(s) in 288.8s`.

While the central was orphaned every read failed *instantly*, so a doomed ladder took 28 s. Once
the orphan recovered, each read got a real connect and blocked for the driver's 20 s timeout:
14 × 20 = 280 s, holding the loop for five minutes and taking the wrist stale. Fixing a bug
changed the timing profile a budget silently depended on.

## 4.5 WCSession goes one-way

**Signature:** `reachable=true` and `sendMessage` times out anyway; or offers arrive and acks
never do.

Observed in both directions in one day. The phone ACKed a hand-back six times
(`write DONE → ACK cursor 6`) and the watch received none, resending every 15 s across three
relaunches. Fixed on the watch side by bounding the drain and by not re-paying the 15 s urgent
timeout once it has failed — one timeout is enough evidence. **The transport wedge itself is
unfixed and is the largest open problem.**

## 4.6 Self-inflicted mistakes worth remembering

- **Removing `bleIdentifier` from a grant dropped the LTK**, because `PodState` decodes both in
  one `if let`. Three takeovers connected and were hung up on ~108 ms after the first command.
  *Read the decoder before deciding a serialized field is inert.*
- **Dropping BG from the ring** was justified by "Loop will not complete a cycle on stale
  glucose" — a manual bolus falsified it by completing a cycle over 9-minute-old CGM.
- **Two off-queue CoreBluetooth calls** in the new code, caught by reading the diff, not by any
  test.
- **A comment claiming a fallback existed** when there was exactly one call site, which had just
  been gated.

## 4.7 Measurement traps

- **RSSI is a validity gate.** One run showed 52% "silence" at median −96 dBm and 0% at −41 dBm.
  Discard any silence not bracketed by adverts stronger than about −75 dBm.
- **There is a ~10–15 s measurement floor**, set by the pod's own 5–10 s advert cadence.
- **Marks written into the live scanner log are unreliable** — the scanner holds the file open
  with a buffered writer and overwrites appended lines. Bound windows by wall clock.
- **App foreground silently changes the phone's connection model** (§2.2).

---

# PART 5 — What's left

- **~30 s of self-inflicted reclaim latency.** The pod connects in 0.53 s and answers a status
  read within 8 s; then the driver's 4 s idle-disconnect drops the link out from under the
  ladder's own in-flight read, which burns its full 20 s timeout before retrying. Suppress the
  idle-disconnect while a read is outstanding, or drop the ladder's per-read timeout to a few
  seconds. **Latency only — 36/36 cycles still enacted.**
- **The WCSession one-way wedge** (§4.5). Root cause unknown; both directions affected.
- **`recreateCentral` may no longer be needed at all.** It exists for a peripheral wedged in
  `.connecting`, and the churn producing those wedges was largely ours. It fired zero times
  overnight. Remove it on data, not argument.
- **The reclaim ladder itself may be removable.** It ran to completion zero times overnight;
  every reclaim either found the link up or reconnected. It is now a fallback, not a mechanism.
