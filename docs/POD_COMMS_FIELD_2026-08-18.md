# Pod comms — what the 2026-08-18 field session established

Written the night of, from build 112's own instrumentation. **Read this before theorising about
pod reclaim failures**, because three plausible explanations were held and discarded in one
evening, and two of them are still repeated in older comments.

---

## The headline

**The reclaim failures are dominated by the G7 holding a near-continuous BLE scan, not by our own
concurrency.** Both alternatives were live theories during the session; the instrumentation
settled it on its first run.

---

## What was measured

`[pod-contend]` lines, loan e126, 22:22–22:32:

| ladder | started | g7direct age at start | outcome |
|---|---|---|---|
| L1 | 22:22:16 | never | OK — link already up, 0 reads |
| L2 | 22:23:25 | never | FAILED, 14 reads, 28.3 s |
| L3 | 22:23:25 (+0.1 s) | never | FAILED, 14 reads, 28.2 s |
| L4 | 22:25:25 | never | FAILED, 14 reads, 28.4 s |
| L5 | 22:26:13 | never | FAILED, 14 reads, 33.3 s |
| L6 | 22:26:38 (+25.7 s) | **0 s** | FAILED, 14 reads, 28.2 s |
| L7 | 22:29:05 | 147 s | FAILED, 14 reads, 28.2 s |
| **L8** | 22:31:07 | **269 s** | **OK, 2 reads, 4.8 s** |
| **L9** | 22:31:39 | **300 s** | **OK, 2 reads** |

The G7's own radio, same window:

```
22:22:00  g7-ble scan STARTED
22:26:37  ad DISCOVERED          ← 4 m 37 s of unbroken scanning
22:26:38  didConnect, reading 148
22:26:49  didDisconnect
22:26:51  scan STARTED
22:31:37  ad DISCOVERED          ← 4 m 46 s of unbroken scanning
```

**The G7 scans roughly 4½ minutes out of every 5**, on its own central, waiting for one
advertisement. Every pod reclaim therefore runs against an active competing scan.

Both successes came when the G7 had been quiet ≥ 269 s. Pod idle time explains nothing (L4 idle
88 s failed; L8 idle 84 s succeeded).

**Caveat, stated because the sample is small:** two successes. L8 also began inside a G7 scan
window and still succeeded, so the relationship is not a clean gate. Treat this as the strongest
available correlation, not a proven mechanism.

---

## Ruled OUT — do not re-litigate without new evidence

### Our own reclaim concurrency is real but NOT the cause

`reclaimPodForDose` has two callers (`WatchDoseEnactor:68` automatic, `WatchLoopManager:2240`
manual) and no reentrancy guard, so two ladders can run at once — confirmed twice (L2/L3 0.1 s
apart, L5/L6 25.7 s apart).

**But L4 and L7 ran alone and failed identically.** Concurrency doubles radio pressure for nothing
and is worth fixing, but it is not the disease. This was asserted as the root cause on
2026-08-18 evening and that assertion was wrong.

### `configure FAILED … notReady` is a symptom, not a finding

`notReady` is thrown by `getCommandCharacteristic()` returning nil
(`PeripheralManager+OmnipodKit.swift:54`) — i.e. services were never discovered, which is what
being disconnected means. The log already prints `servicesNil=true` beside it. It fires once per
read because each read attempts configuration on a disconnected peripheral. It is noise; build 112
suppresses most of it.

---

## Still open, and worth acting on

### `loanTakeoverPodId` goes nil mid-ladder — cause unknown

**First reading was wrong and is recorded here so it is not repeated.** I claimed connectOnDemand
tears down the reclaim scan because "a reclaim is not a takeover." It is: `reclaimPodForDose` →
`podLoanEscalateReclaim()` → `escalateLoanReclaim(podId:)` sets `loanTakeoverPodId`
(`BluetoothManager.swift:607`, `:630`), so the guard at `:881` **does** cover reclaims.

What the log actually shows is stranger. At 17:50:35, 26 s into a live reclaim ladder,
connectOnDemand ran its **unguarded** path:

```
17:50:09  [loan-takeover] scan started (filter=…)      ← marker armed
17:50:35  [connectOnDemand] fresh-discovery scan started    ← guard did NOT fire
17:50:39  [connectOnDemand] no fresh discovery in 4s — cold connect fallback
```

Had the marker still been set we would have seen `[connectOnDemand] takeover: continuous scan
(no 4s teardown)`. So **something cleared `loanTakeoverPodId` while the ladder was still running**,
and that clearing let connectOnDemand stop and replace the ladder's scan.

Two candidates, neither confirmed:

1. **Adoption** (`:1412-1415`) nils it when a matching pod advertisement is seen. The pod never
   connected in this window, so this would mean an advert was matched and the connect still failed.
2. **A concurrent ladder's release.** `releaseConnection()` → `cancelLoanScan()` clears it
   (`BlePodComms.swift:118`), commented as "the scan must not outlive the reclaim ladder." With
   two ladders live, ladder A's release would clear the marker out from under ladder B — which
   would make the concurrency bug matter after all, via a mechanism nobody designed for.

The post-dose release was armed for +12 s (17:50:46), i.e. AFTER the observation, so the ordinary
release path is not the explanation.

**This is the next thing to measure, not to fix.** Every set and clear of `loanTakeoverPodId`
should name its caller; the answer then falls out of one line.

### The frozen UI is the same bug wearing a different costume

Six `[loop] OPENED by user` events landed within one second at 22:29:30 — the user tapping
repeatedly because nothing responded. Every tap registered.

The glance's own comment explains it: *"each tick takes the loan controller's queue, which the pod
also uses."* L7's ladder held that serial queue 22:29:05–22:29:33, so the glance could not repaint
for ~28 s. The state changed on the first tap; the screen simply could not say so.

**So "the UI freezes" and "the pod won't connect" are one problem, not two** — and the UI half
disappears if reclaims stop costing 28 s. Worth fixing independently anyway: a display that cannot
repaint while the radio is busy is a display that fails exactly when it is being watched.

---

## What NOT to do

The standing rule still holds and this session does not overturn it: **never buy takeover
reliability with G7 radio time.** The G7 is the glucose source; a pod reclaim that succeeds by
starving it is a worse system. Any fix here should reduce *our own* contention (the two above)
or coordinate with the G7's scan cycle — not pre-empt it.

---

## Test-suite flakiness observed the same night (not a pod issue — recorded so it is not lost)

**Two flaky tests in `LoopTests` gated a dosing build tonight, on different runs.**

1. `LoanBooksHarnessTests.testInheritedTempSpanBooksOnBothSides` — genuinely wall-clock-phase
   dependent: `d5` measured 0.0077, 0.0212 and 0.0277 on consecutive runs of identical code,
   because the IOB integrals sample on an absolute grid while the test anchored its geometry to an
   unaligned `Date()`. **Fixed** by pinning `now` to a 5-minute boundary; its threshold had
   already been tuned once against an integral bound that upstream had since deleted.

2. `PodLoanPhoneControllerTests.testStaleOfferMustNotClampALaterEpochsDosesToItsOwnHandbackTime` —
   failed once inside the full 97-test gate ("expected a grant, got Optional(…)"), then passed
   58/58 when its suite ran alone, then the full gate passed on re-run. **Not fixed.** It carries
   the same two smells: `Date().addingTimeInterval(-.minutes(30))` for its geometry and
   `wait(for:timeout: 5)` for its synchronisation. A 5-second expectation under a loaded machine
   is a load-dependent timeout, not a logic assertion.

**Why this matters more than it looks.** A gate that fails intermittently on a build that touches
dosing is a gate people learn to re-run rather than believe, and that is exactly how a real
failure gets waved through. Tonight it was re-run and passed — which is the correct outcome and
also the habit worth not forming.

The fix for (2) is the same as for (1): make it deterministic rather than retry it. Pin the clock,
and replace the wall-clock expectation with something that does not depend on machine load.
