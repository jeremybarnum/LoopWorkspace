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

**JB this needs more definition - what does clean room mean, and what are essentially the titles of each of the columns.  I think you're saying that that the first column is something like "windows of unavailability" or "pod not reachable". ** Clean room (loan ended, both apps quit, both radios off, one hour, close range):

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

**JB for the purposes of this document I think we need to move away from "pure" to refer to the various branches.  it's basically current dev, and next dev, and our sport mode implementations on each code base.  Let's refer to them accordingly**

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

### 2.3.1 The connection budget, and why an overlap costs more than one slot

This is the load-bearing constraint of the whole watch design, so it is worth stating exactly,
including where the confidence runs out.

**What is documented:** watchOS allows an app roughly **two simultaneous BLE connections**
(WWDC guidance). Sport Mode needs exactly two — pod and G7 — so we sit permanently at 100% of
budget with no headroom.

**What we measured:** with `hold-for-loan` on, the pod hung up every ~5 s (§1.8) and
`autoReconnect` re-bid instantly. Within ~13 minutes G7 could no longer connect at all:
`CBError 11` ("maximum number of connections"), repeating every 2 s until the pod link was
released, after which G7 recovered on its next advertising window. Both ends of that are
measured, and the pod ledger showed `ORPHANED=0` throughout — we were not leaking intents.

**What is inferred:** that a reconnect *transiently* claims two slots — the old link not yet
fully torn down while the new pending connect already counts. That is the only mechanism we
can see that turns "1 pod + 1 G7 = 2" into a refusal, and it explains why the failure was a
race that took minutes to bite rather than an immediate hard stop. **We have not proven it.**
It could equally be that a pending connect and an established one are counted differently, or
that the budget is smaller than two under some conditions.

**Why the narrative matters even so:** the effect is not confined to our app. When our pod link
flapped, **the G7 stopped delivering entirely** — the loop went blind with the phone away,
which is the exact scenario Sport Mode exists for. So the budget is not a tuning parameter to
be optimised against; it is a hard constraint, and any design that holds the pod link idle will
eventually spend G7's slot.

*(One earlier draft went further and claimed we had wedged the sensor for Dexcom's own app.
That was wrong and is retracted: `CBError 11` is a CENTRAL-side limit — our own stack — and a
G7 serves several simultaneous connections, which is the founding premise of the D2W piggyback
work. Jeremy's observation of the Dexcom app also being without data in that window remains
unexplained and uninvestigated.)*

### 2.3.2 The watch's keep-alive is NOT the same thing as "foreground"

Easy to conflate, and conflating them is what put the wrong gate in the driver.

During a loan the watch runs an **`HKWorkoutSession`**, for a reason that has nothing to do with
BLE: without it watchOS suspends the extension and **the loop stops running at all** — no
cycles, no dosing, no glucose ingest. It is what makes a wrist-driven closed loop possible.

`isAppForeground`, by contrast, means the user is *looking at the screen*. The two are
independent: the keep-alive holds the app **running** for the whole loan; foreground flickers
on and off as the wrist raises. Field data shows a 7-minute stretch with no foreground
transition at all during an active loan.

That distinction is why `shouldHoldConnection` was the wrong gate on the watch. It asks "is the
user looking?" and answers "then hold the pod" — which on a phone means responsiveness, and on
a watch means holding an idle link that the pod will terminate (§1.8), spending G7's slot for a
benefit worth ~1.3 s.

**And battery is explicitly NOT the constraint here.** A Sport Mode session is a 1-4 hour
phenomenon, not all-day, and field experience across many sessions has never made battery the
limiting factor. Do not trade away connection reliability to save power; the keep-alive already
costs more than the radio does.

---

# PART 3 — What we built

**"The lean path"** = letting OmnipodKit's own connect-on-demand do the connecting, the way the
phone does, instead of driving the radio from Sport Mode code above it. Concretely:
`bleRunSession` adopts a `PeripheralManager` from `podState.bleIdentifier` while disconnected,
`configureAndRun` connects on demand for the command, and the driver's idle-disconnect releases
it. No scan, no ladder, no escalation. Everything in this Part exists either to feed that path a
usable handle or to stop older machinery from fighting it.

The watch now behaves as a **permanently-backgrounded phone**, with one deliberate exception.

1. **`shouldHoldConnection` returns false on watchOS, unconditionally** (§2.3.2). Release is then
   governed by the driver's own **4 s idle-disconnect**, which resets per session — so a status
   read followed by a dose shares one connection instead of paying for two.

   *What this replaced:* Sport Mode had its own release timer in `PodLoanWatchController`
   (`performPostDoseRelease`, `Lab.podReleaseDelay`, default 12 s) that orphaned the link after
   each dose. That existed **only** to defeat the foreground hold — with `shouldHoldConnection`
   false, the driver already releases, sooner and more precisely. That timer is now redundant and
   is a removal candidate (Part 5).

2. **A per-pod BLE handle cache** (`PodLoanBleIdentifierCache`, keyed by pod address). The watch
   already learned the right handle on adopt and then discarded it, because the pump manager is
   rebuilt from the phone's snapshot at every grant. Now it persists across loans.

   *Open UX idea:* resolve the handle once at pod-pairing time so even the first loan is instant.
   Probably overkill — it saves ~10 s, once per pod, every three days. The cheaper answer is to
   say so in the UI: "first time using Sport Mode with this pod — one-time setup" on that first
   takeover, and nothing thereafter.

3. **Handle substitution at grant intake — before `OmniPumpManager` is constructed.** The timing
   is the point: `BlePodComms.init` immediately calls `connectToDevice(uuidString:)` with
   whatever handle it finds, so substituting *after* construction would be too late — the driver
   would already have acted on the phone's foreign UUID, putting it in `autoConnectIDs` where it
   can never be discovered, which pins `hasDiscoveredAllAutoConnectDevices` false and keeps the
   radio scanning for the whole loan.

4. **No-scan takeover** when a handle resolves. Three cases, only one of them common:

   | case | what happens | how often |
   |---|---|---|
   | **no handle yet** — first loan with this pod | normal discovery scan, then the handle is cached | once per pod (~3 days) |
   | **handle present and resolvable** | connect directly, no scan at all | every loan thereafter |
   | **handle present but iOS no longer recognises it** — app reinstalled, pod replaced | `retrievePeripherals` returns empty *immediately*, fall through to discovery | rare |

   A fourth case — handle recognised but the pod is unreachable — is the only one needing a
   timer, because a bare `connect()` never times out and would hang forever. Hence the 6 s
   fallback to discovery.

5. **No escalation on reclaim when a handle is known.** On watchOS `escalateLoanReclaim` calls
   `recreateCentral()`, which was running on *every dose cycle* (§4.3). Gentle reconnect first;
   the ladder escalates at read 4 if it has not landed, once per ladder.

6. **A wall-clock ladder ceiling (45 s)**, because "14 reads × ~2 s" stopped being true once reads
   became honest (§4.4).

7. **The hand-back stops waiting forever, and stops re-paying a timeout it has already paid.**
   Two separate failures, both from the WCSession wedge (§4.5):
   - *Bounded drain* — after the phone has reclaimed a loan, the watch may still be trying to
     hand back records. It used to resend every 15 s indefinitely; it now gives up after 20
     attempts (~5 min) and closes to idle. Safe because a drain delivers records the phone has
     already committed.
   - *No repeated urgent timeouts* — `sendMessage` can hang for its full 15 s while WCSession
     claims the phone is reachable. Every retry re-chose that path and re-paid 15 s. One timeout
     is now enough evidence; subsequent sends go straight to the queued path. This is the "End
     feels sluggish" fix.

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

## Result — bench 2026-08-23, build 1085: the reclaim fix validated on hardware

The reclaim-latency fix shipped 2026-08-20 and, until today, had **never run on hardware** —
two prior attempts at the second leg died to app relaunches. Both legs now measured, one loan,
new pod (`177E6B7F`), phone present:

| leg | reps | reclaim times | median |
|---|---|---|---|
| idle 0 s | 5 | 5.0 · 10.8 · 13.7 · 10.2 · 15.1 s | ~10.8 s |
| idle 300 s (cold pod) | 3 | 12.3 · 10.9 · 9.3 s | ~10.9 s |
| **old code, for comparison** | — | — | **~30.5 s** |

**~3× faster, and idle time is irrelevant.** A pod left alone 5 minutes — past its ~3-minute
self-disconnect, fully cold — reclaims exactly as fast as one released seconds ago. The residual
~10 s is entirely our own read-starvation overhead, not the pod's state. The 2×2 experiment is
closed (the old-code cold cell died twice and is now moot).

Health counters across both legs: **0 orphaned `PeripheralManager`, 0 `central=nil`, 0
escalations** (6 × `NO escalate`), 0 ladder abandonments, 4/4 loop cycles enacted, no app deaths.

**The residual is structurally rigid, which is the useful finding.** Every reclaim in both legs
was *exactly* "read 1 starves, read 2 succeeds" — 2 reads, ~10 s — with one 5 s exception in 8
ladders. It is not a distribution; it is a constant. Read 1 waits on a superseded
`PeripheralManager` for the full 6 s watchdog (it was 20 s before the watchdog, which is the
entire 30 s → 10 s win), then read 2 lands on the current object. **The lean rewrite — reads
themselves drive the connect, no parallel path creating object swaps — removes the cause and
takes every reclaim to ~5 s.** That is now the only thing between us and the floor.

First field sighting of `g7pending=`: the G7 client parks a pending connect for **299 s** at a
stretch between deliveries. **This is NORMAL, not pathology** (pure-line triage, 2026-08-23):
the standing pending connect IS the piggyback mechanism — `connectPeripheral` waiting for the
sensor's next window is how triggers a/b work. Do not "fix" it. The pathological cases are
(1) an ORPHANED pending from a dead process, with no living owner, and (2) the budget
arithmetic it implies: G7-pending (1 slot, near-always) + pod link (1 slot during dose windows)
= routine zero headroom, so any third connect — a takeover retry, an orphan — tips into `#11`
(the 5-refused-in-3 s burst at acquisition, 15:09). Consequence for any cancel-stale-connects
fix: scope it to the POD identifier only — cancelling the G7 standing pending kills
acquisition; the G7 manager re-issues its own connect fresh.

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

## 4.64 Keepalive grants RUNNABILITY, not execution (overnight soak 2026-08-25)

An HKWorkoutSession keepalive does not mean the app runs — it means the app MAY run when
events arrive. Proven by starvation: phone radios off, watch/pod/sensor all at range, loan
active, keepalive held (`keepalive running(soak)` in every gap line), battery 100% — and the
app executed roughly ONCE AN HOUR (the OS allowance), then not at all for 5.8 hours. No kill,
no relaunch: the same process woke at 06:08 with `GAP 20922s`. Every prior soak had at least
one radio delivering events, which is why this was never visible.

Consequences, all of which held: dosing safety is the POD's own property (temp runs to its
programmed end, then scheduled basal — no radio required); loan/epoch state survives arbitrary
suspension (one epoch crossed the whole coma and reconciled to a clean ledger); and alerting
must come from OUTSIDE the process — which is why the dead-man rungs are pre-scheduled
UNNotifications.

**OPEN (top of the list): the from-suspension rung delivery is unverified.** The 20-minute
rung fired on schedule when the app had runtime (faraday, 2026-08-24), but after the fully
dark night no Loop Failure notifications were found on the watch face. Either they fired
unnoticed and were lost, or deep suspension / sleep Focus / a workout-session interaction
suppressed them — different bugs, one decisive test: stall the loop, touch NOTHING for 25+
minutes, then read the watch's notification center.

## 4.65 The cb: connect clock was never wired (instrument correction)

`PodLoanConnectClock` — the independent clock that stamps CoreBluetooth's own
didConnect/didDisconnect/didFailToConnect so ladder polling can be checked against ground truth
— was ported with its three `note*` entry points and **zero call sites**. Every `cb:` field this
branch ever logged read `didConnect never (n=0)` structurally, not observationally.

**Treat every pre-2026-08-22 `cb:` field in this branch's logs as void.** Conclusions that
leaned on them survive only where the intent ledger (a separate, correctly-wired system)
corroborated. Wired 2026-08-22; from then on the trail, `lastFail=CBErrorDomain#N`, and the
wedge signature below are real.

## 4.66 Force-quit strands SYSTEM-level pending connects (peer-measured; remedy shipped)

From the pure/SportMode line's field session (real user, App Store build): CoreBluetooth
connect requests live in bluetoothd, not in the app — a force-quit mid-retry leaves pending
connects **no living process can cancel**. Slots stay consumed and the radio goes progressively
blinder: takeover refused with `#11` while the pod advertised beside it → user force-quit and
retried (the natural response) → next ladder heard ZERO adverts in 108 s while the phone
reconnected to the same pod in 6.6 s. Each round worsened it. **A watch Bluetooth toggle
flushed it** — first-try success after.

Consequence shipped here (2026-08-22): the takeover-failure message now branches on a **wedge
signature** — any `#11` during the attempt, or an attempt in which no connect ever landed
(the pod is known-present at takeover; the phone released it seconds ago) — and a wedged
failure says *toggle watch Bluetooth*, because "try again" actively feeds this failure mode.
The signature is deliberately NOT surfaced on reclaim failures, where a quiet pod also
produces zero connects; there the raw `lastFail=` field carries the evidence instead.

Takeover read lines now also carry `g7pending=` — a `#11` cannot name its holder from the pod
central's census (the G7 client is a separate CBCentralManager), and a pending G7 connect is
the usual suspect for the missing slot.

**The real fix — cancelling orphaned connects for known pod+G7 identifiers at launch and
teardown — is deliberately NOT built here yet.** The pure line is building it fresh; the port
takes it after it has field time. Cancelling at launch touches every reconnect flow and has no
bench coverage without hardware.

## 4.67 TWO wedges, TWO remedies — never cross-contaminate the guidance

There are two distinct "it's wedged, toggle something" failure classes, and giving one's
remedy for the other wastes a stranded user's time (pure-line triage 2026-08-23, their
WCSESSION_7006_BRIEF @ 520eebd6 carries the full table; this is the mirror):

| | BLE orphan wedge | WC transport wedge |
|---|---|---|
| signature | `#11` refusals / ladder-never-connects on the POD link; adverts go quiet | grants/acks vanish one-way; `isWatchAppInstalled=false` with the app present; #113/#108 fire |
| lives in | bluetoothd slot bookkeeping (orphaned pending connects) | the PHONE's WCSession daemon |
| remedy | **watch Bluetooth toggle** — field-proven first-try; the launch reap (§ below) now automates the same cleanup | **phone-side reset** (reboot; historically a TestFlight install also cleared it). Watch-side actions do NOT touch it — proven 2026-08-23: toggles, force-quits, and a watch reboot all failed against it |
| our message | takeover-failure wedge branch (BLE signature only) | #113 request-timeout / #108 grant-unconfirmed |

Evidence for the phone-daemon locus: four stereo-logged occurrences in one evening
(watch→phone alive, phone→watch dead, every watch-side remedy failed), plus the pure line's
8/17 case that survived force-quitting BOTH apps and cleared only on a phone-side event.
Candidate trigger, first ever logged: the phone's clock stepping BACKWARDS (in-flight time
re-sync) — bench-reproducible via airplane mode + manual clock change, untested.

Nuance on `appInstalled=false` alone: Jeremy's earlier occurrences cleared with a watch BT
toggle, so the flag by itself does not decide the class — transient flag-flaps ride install
churn and recover watch-side; the TRANSPORT wedge is the persistent one-way case. The glitch
notice keeps the watch-toggle advice as first-line; escalate to the phone-side remedy when
the one-way signature (#113/#108) is present or the toggle fails.

## 4.7 Measurement traps

- **RSSI is a validity gate.** One run showed 52% "silence" at median −96 dBm and 0% at −41 dBm.
  Discard any silence not bracketed by adverts stronger than about −75 dBm.
- **There is a ~10–15 s measurement floor**, set by the pod's own 5–10 s advert cadence.
- **Marks written into the live scanner log are unreliable** — the scanner holds the file open
  with a buffered writer and overwrites appended lines. Bound windows by wall clock.
- **App foreground silently changes the phone's connection model** (§2.2).

---

# PART 5 — What's left

## Removal candidates, ranked by how much evidence we have

The overnight run (36/36, phone off) makes several things look vestigial. Ranked by confidence,
because "it did not fire once" is weaker evidence than it feels:

| candidate | evidence | verdict |
|---|---|---|
| **Sport Mode's own post-dose release timer** (`performPostDoseRelease`, `Lab.podReleaseDelay`) | Structurally redundant: it existed only to defeat the foreground hold, which is now off. The driver's 4 s idle-disconnect is strictly better. | **Remove.** Argument, not just data. |
| **`recreateCentral()`** | Fired 0 times overnight. It exists for a peripheral wedged in `.connecting`, and the churn producing those wedges was mostly ours. | **Probably remove** — but it is the recovery for a genuinely wedged stack. Wait for a few more sessions. |
| **The reclaim ladder itself** | Ran to completion 0 times; every reclaim either found the link up or reconnected. | **Not yet.** It is now a fallback rather than a mechanism, and it is the only thing standing between an unreachable pod and a missed dose. |
| **The read-4 mid-ladder escalation** | Fired 0 times. | **Keep for now.** It is the *only* remaining scan-adopt path — removing it removes recovery for a pod we cannot address locally, which is the case scan-adopt was originally measured on. |
| **The 45 s ladder ceiling** | Never hit. | **Keep.** It is a cheap bound whose whole purpose is to be inactive; it exists to stop the 288 s case (§4.4) recurring. A safety bound that never fires is working. |

One night with a healthy pod is not evidence that recovery paths are unnecessary — it is
evidence that recovery was not needed *that night*. Remove the top row on the argument; make the
rest earn it across sessions that include a dead or distant pod.

## Known problems

- **~30 s of self-inflicted reclaim latency.** The pod connects in 0.53 s and answers a status
  read within 8 s; then the driver's 4 s idle-disconnect drops the link out from under the
  ladder's own in-flight read, which burns its full 20 s timeout before retrying. Suppress the
  idle-disconnect while a read is outstanding, or cut the ladder's per-read timeout to a few
  seconds. **Latency only — 36/36 cycles still enacted.** Highest-value next fix.
- **The WCSession one-way wedge** (§4.5). `isReachable` true, `sendMessage` times out; or offers
  arrive and acks never do. Seen in both directions in one day. We have mitigations on the watch
  side and **no root cause.** Largest open problem — and now confirmed in production.

  **CONFIRMED ON A REAL USER, APP STORE BUILD (2026-08-21, via the pure/SportMode line).**
  Caitlin's production build 108, a TestFlight install on devices `devicectl` has never touched,
  hit it during a 92-minute loan: a 25-minute window with **0 inbound phone→watch messages and 7
  successful outbound**. The consequence was not cosmetic — that watch loop is glucose-triggered,
  so with no inbound glucose **no cycle ran for 25 minutes** (no CYCLE VERDICT between 14:59 and
  15:24) while she was descending after a genuine "very likely low in 21 mins" warning, bgAge
  climbing past 500 s with her watching. Nothing unsafe resulted (no-change temp, IOB 0.5, floor
  82) but it stopped looping during the window where looping mattered.

  This also **refutes a hypothesis we briefly held**: that the wedge might be an artifact of
  development installs (every occurrence on this branch had been on a `devicectl` build, and our
  first TestFlight install of the day ran clean). It is not. Do not deprioritise it as a dev-only
  problem. The remaining open question is the other direction — whether a `devicectl` install
  DEGRADES a healthy App Store registration — which is still untested.

  Note the port is *less* exposed than the pure line for glucose specifically, because direct-G7
  delivers here (34/34 overnight) and can carry a loan when the relay is wedged; on her build the
  direct client delivers **zero** and every reading comes by relay, so a wedge there is total.
  Grants and hand-backs ride WCSession on both lines and are exposed equally.
- **The watch app dies unexplained** — four occurrences on 2026-08-21: launches, fully
  initialises, PAINTS UI, dies at ~2 s. Not a startup crash (it renders), not jetsam (it gets that
  far), not auto-relaunched (stays dead until tapped). No `.ips` in the app container. Note the
  log's clean endings are NOT a truncated tail — `SportLog.append` does a real `write` + `close`
  per line, so the loss window is milliseconds; the silence is a genuinely idle app. What we lack
  is the ability to distinguish IDLE from DEAD in our own log (a periodic heartbeat would fix
  that), and a captured system termination record — `os_log` output survives death and a
  sysdiagnose should carry it, but the one on-demand reproduction we had was wasted on a
  malformed `devicectl diagnose` invocation (`--device` vs `--devices`).

- **The watch stops receiving the sensor entirely — D2W included.** (Jeremy, 2026-08-21,
  superseding the earlier "which device was it" hedge: D2W is the Dexcom WATCH app, phone-
  independent, so this is a watch-side, system-level observation.) Precise symptom: start a
  loan; the phone leaves (Faraday cage, radios off, powered off, or plain distance — the
  mechanism of departure does not matter); after **~15 minutes** BG stops flowing to our app
  AND to D2W. Two independent apps on one shared radio going dark together means the failure
  is below the app layer. The ~15-minute onset is the diagnostic signature: a static budget
  problem would bite immediately, so this looks like **accumulation** — something held or
  leaked per reclaim/G7 cycle (~3 cycles ≈ 15 min) until the watch's TOTAL connection budget
  is exhausted and the system can open no new links for anyone. The phone's role is
  topological, not causal: with it present the sensor's primary collector is the phone; with
  it gone, all sensor traffic concentrates on the watch. Consistent with the hold-for-loan
  `CBError 11` event and with the old "G7 self-recovers ~25 min after takeover" observation —
  recovery-by-timeout is what a leaked resource aging out looks like.
  **Test when a sensor exists:** reproduce with phone departed, and watch the intent ledger,
  `devices` count, and G7 connection events across the 15 minutes to see what accumulates;
  simultaneously check D2W on the wrist so its failure is timestamped, not recalled.

## UX follow-ups

- Name the first takeover with a new pod as one-time setup, so the ~10 s discovery reads as
  expected rather than slow (Part 3 item 2).
- The hand-back "ending…" state should say what it is waiting for; the transport wedge makes it
  silent for minutes.
