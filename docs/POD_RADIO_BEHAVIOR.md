# How the pod's radio actually behaves — measured 2026-08-20

Replaces inference with measurement. Every number here came from a passive Mac BLE
observer (`ops/g7watch-mac`) that only ever scans — it never connects, so it cannot be
the thing it is measuring.

## Method, and two traps that invalidated earlier runs

**RSSI is a validity gate.** At long range "silence" means *we failed to hear*, not *the
pod failed to speak*. One run showed 52% silence at median RSSI -96 dBm; the same setup
in one room showed 0% at -41 dBm. **Discard any silence not bracketed by adverts stronger
than about -75 dBm.**

**There is a measurement floor of ~10-15 s.** The pod's own advertising cadence is 5-10 s,
so a connection held for less than that is indistinguishable from a normal gap. Anything
we call a "hold" must exceed the floor.

**Marks written into the live scanner log are unreliable.** The scanner holds the file open
with a buffered writer at a tracked offset; a shell append gets overwritten by the next
flush. Bound windows by wall-clock instead.

## 1. The pod's natural rhythm (nothing connected)

Clean room: loan ended, Loop quit on phone and watch, both radios off, one hour, close range.

```
  0-2s   43.9%      10-30s   1.8%
  2-5s    8.4%      30-60s   0.0%
 5-10s   45.7%     60-300s   0.2%   (two events: 258s, 182s)
```

**98% of gaps are under 10 seconds.** The pod is intrinsically chatty. It does have quiet
spells — two in an hour, longest 258 s, 10.9% of wall-clock — but they are the exception.

## 2. A connected pod is an invisible pod

BLE peripherals stop advertising while connected, and the pod holds one connection at a
time. So **"the pod isn't advertising" and "someone else has it" are the same observation.**
Every silence longer than the floor is a connection window belonging to somebody.

## 3. next-dev's phone has TWO connection models, switched by app foreground

```swift
var shouldHoldConnection: Bool {
    if isAppForeground { return true }     // ← the switch
    #if os(iOS)
    return podType.isDash && Storage.shared.podKeepAlive.value.keepsPodConnectedInBackground
    #else
    return false                            // watchOS collapses to isAppForeground
    #endif
}
```

Measured, closed loop, pod at close range:

| phone state | pod held |
|---|---|
| **foreground** | windows of 41 s, 59 s, 108 s, 244 s, 655 s — separated by 1-2 s blips. ~50%+ of wall-clock. Effectively a standing connection. |
| **backgrounded** | **zero holds >28 s across 12 min and multiple enact cycles. 0% unavailable.** |

`connectOnDemandEnabled` defaults true, but **foreground silently overrides it**. Any
measurement of "how next-dev behaves" taken with the app on screen is measuring the wrong
mode — which invalidated several hours of this day's observations before it was caught.

## 4. Delivery does NOT require a connection — this is the big one

| bolus | expected delivery time (~0.05 U/s) | observed hold |
|---|---|---|
| 0.10 U | ~2 s | none — gaps 5-11 s, indistinguishable from idle |
| **2.8 U** | **~56 s** | **none — gaps 5-13 s, pod advertising throughout** |

Delivery confirmed audibly (the pod clicks) while it kept advertising every 5-6 seconds.

**The pod advertises while it is delivering.** Loop commands the bolus, drops the link in a
couple of seconds, and the pod delivers autonomously; completion is picked up on a later
status read. Hold time does not scale with bolus size at all.

`estimatedDuration(toBolus:) = units / Pod.bolusDeliveryRate` exists, but its only consumer
is `DeviceDataManager` for bookkeeping. **Nothing in the BLE layer uses it.** Of the four
candidate hold policies — fixed long hold, max-bolus-sized, actual-bolus-sized, or
command-and-release — Loop implements the last, and the other three solve a problem that
does not exist.

Temp basals are the same story: every enact window with the app backgrounded was at or
below the measurement floor.

## 5. The two lines, side by side

**Pure (`SportMode`) — the entire connection model:**
```swift
if autoConnectIDs.contains(peripheral.identifier.uuidString) {
    central.connect(peripheral, options: nil)     // on disconnect, reconnect. that's it.
}
```
`central.connect()` never times out, so this is a standing bid that resolves whenever the
pod is reachable. No ladder, no scan-adopt, no teardown logic.

**next-dev — connect-on-demand** plus idle-disconnect, C00A fault-scan while idle,
`freshConnect`, a 4 s teardown, heartbeat and delayed probes.

**Our watch during a loan** orphans after each dose (`Lab.podReleaseDelay`, default 12 s)
and reacquires with a 14-read / 28 s scan → discover → adopt ladder.

## 6. What the phone does that we don't

The phone never scans to reacquire. `PeripheralManager.configureAndRun` issues a **bare
pending connect on a `CBPeripheral` it already holds**, and iOS reacquires the pod itself —
no discovery step. The watch needs a discovery scan exactly ONCE, on its first takeover,
because it has never seen the pod and CoreBluetooth peripheral UUIDs are per-device. After
that it has a peripheral and could reacquire the phone's way.

Field evidence it already works: ladders **L9 and L12 succeeded with `adverts=0`** — no
advert ever heard, the bare pending connect simply landed.

So the watch runs an application-level reclaim ladder *on top of* a driver that already
does connect-on-demand. Two mechanisms for one job, and they interfere: the ladder polls
every 2 s, each poll enters `configureAndRun`, and those polls' fast `notReady` throws were
cancelling the driver's own in-flight connects (6 of 6 cancels, fixed 2026-08-20).

## Open questions this does not answer

- Whether a held link over a multi-hour loan affects pod battery or link stability.
- How force-reclaim behaves against a held link (the phone's escape hatch must still work).
- Whether the watch's enact truly routes through `configureAndRun` (same OmnipodKit, so it
  should, but not yet traced end to end).
- The overnight 180 s metronome: consistent with ordinary foreground dosing holds, but the
  RSSI gate was never applied to that sample, so it may be partly range artifact.

---

## 7. hold-for-loan: tested 2026-08-20, and it FAILS — keep orphaning

`Lab.podReleaseDelay = -1` (never release) + `connectOnDemandEnabled = false`, radios off,
loan epoch 149. The pod side worked perfectly: `L4 OK after 0 read(s) — link already up`,
`enact=ok`. Then at ~20:19 the G7 died and the ring went orange.

```
20:21:10  [g7-ble] didFailToConnect DXCMqL
          error=The system has reached the maximum number of connections   (CBError 11)
```

### Why 1 pod + 1 G7 exceeded a 2-connection budget

It never held three connections steadily. **The pod hangs up on an idle held link** —
`Code=7`, peripheral-initiated, every ~5 s:

```
20:20:07  Pod disconnected  → timedConnect → open=1
20:20:09  Pod connected
20:20:14  Pod disconnected (Code=7) → timedConnect → open=1
20:20:15  Pod connected
20:20:20  Pod disconnected (Code=7) → timedConnect → open=1
```

With connect-on-demand off, `autoReconnect` re-bids instantly, so every drop opens a window
where the old link has not finished tearing down and a new connect is already pending —
transiently two pod slots. G7 retries every 2 s and kept landing in those windows. The pod
ledger stayed clean throughout (`ORPHANED=0`), so this is a race, not a leak.

**Pure gets away with holding the pod because the phone's keep-alive constantly polls it**
("the keep-alive's periodic status refresh maintains the link"). We held it with NO traffic
between doses, and the pod terminated it. A held link needs traffic to survive.

### Orphan-between-doses is load-bearing for TWO reasons

Not over-engineering, as this session briefly concluded:
1. it frees the second BLE slot for G7, and
2. it avoids fighting the pod's own idle-disconnect.

A watch cannot copy Pure's standing connection, because a phone has no G7 competing
in-process.

### RETRACTED: the "we wedged the sensor" claim

An earlier revision of this section claimed a G7 accepts one connection at a time and that
our retry storm locked out the Dexcom app. **That is wrong and contradicts this project's
founding result** — the D2W piggyback works precisely BECAUSE the sensor serves several
simultaneous connections (phone + watch + our stack). See the piggyback work.

`CBError 11` is a **central-side** limit — the watch's own BLE stack ran out of connection
slots. It says nothing about what the sensor will accept, and gives no basis for a claim
about other apps' access to it.

Jeremy did observe the Dexcom app without data during this window; that is unexplained and
was NOT investigated. The obvious candidate was never checked: which device that app was on,
and whether that device's radios were off at the time. Do not treat it as evidence of
anything until someone actually looks.

### The deadlock

Post-dose release only fires AFTER a dose:

```
no glucose -> no cycle -> no dose -> no post-dose release -> link never freed -> no glucose
```

It broke only because the pod hung up (`Code=7`) at 20:26:15 *after* the toggle had already
been reverted, so `autoReconnect` no longer re-grabbed it. Had it still been off, this would
have stayed wedged indefinitely. Recovery then took ~8 min waiting for the G7's next
advertising window (300 s grid); glucose and backfill both landed at 20:34:37.

### Queue items from this

- **Release the pod link on a stale-loop condition**, not only after a successful dose.
- **Back off the G7 retry** instead of hammering every 2 s when refused — the hammering is
  what appears to wedge the sensor for all clients.
- Reacquire via bare connect from a persisted per-pod `bleIdentifier` (see §6); the watch
  currently learns its own identifier on adopt and discards it on the next grant, because
  the manager is rebuilt from the phone's snapshot each time.
