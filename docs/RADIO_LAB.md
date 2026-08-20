# Radio Lab — runtime switches instead of reinstall bisection

Jeremy, 2026-08-20 01:05: *"the installs are so painful that we can't afford to troubleshoot that way.
We need debug toggles on the watch that do G7 a, b and c, and that also do different approaches to the
pod... a complicated series of switches, but it might be easier than this painful guessing with long
install cycles."*

Exactly right, and the arithmetic is stark: an install cycle tonight cost 30–90 minutes and sometimes
poisoned the companion registration; a runtime toggle costs 10 seconds and cannot. One build carrying
all switches converts branch-bisection (impossible: next-dev changed BOTH stacks at once) into
knob-bisection (one dimension per run).

**A precedent already in-tree:** `connectOnDemandEnabled` and `lowPowerMonitorEnabled` already read
UserDefaults at each use (`BluetoothManager:476,486`) — runtime-switchable today, just with no UI. The
lab is that pattern, surfaced.

---

## The switch set (maps 1:1 to `BLE_CONFIGURATION_SPACE.md`)

### G7 acquisition — three independent toggles, not a picker
| switch | default | seam |
|---|---|---|
| (a) ride system link | ON | the `retrieveConnectedPeripherals` block at scan-start, `G7BluetoothManager.swift:270–280` |
| (b) connection events | ON | registration logged "trigger b armed", `:302` |
| (c) own scan | ON | `scanForPeripherals`, `:297` |
| (c) guard-band | OFF | NEW: scan only ±20 s around the predicted window. Anchor = last `messageTimestamp` (grid exact to ppm; predicted 21:31:38 vs observed 21:31:37.969 tonight) |

Independent toggles because the discriminating runs are `b-only`, `c-only`, and `b+guard-band-c` —
a picker can't express those.

### Pod link — one picker + one number
| control | options | seam |
|---|---|---|
| link mode | **on-demand** (ship) / hold-for-loan / hold-with-G7-yield | `connectOnDemandEnabled` + `shouldHoldConnection`, `BluetoothManager:476,607` |
| post-dose release | 0 s / **12 s** / 60 s / never | the `post-dose-release +12s` timer, `PodLoanWatchController` |
| bisect the 180 s hold | disable heartbeat probe / disable alarm scan | `delayedConnectProbeActive:641`, `lowPowerMonitorEnabled:486` — to find WHO re-acquires within ~3 s of every release |

"hold-with-G7-yield": hold the pod but release for the ±20 s predicted G7 window — the arbitration
experiment, expressible only because the grid is exact.

### Readouts on the same screen (else every run needs a log pull)
- config line, e.g. `g7=a+b+c pod=onDemand rel=12s`
- pod: `adverts=N last=Ns` (exists) · `isScanning` · **didDiscover-ANY counter** — the deaf-vs-misfiltered discriminator; if it sees zero peripherals of any kind while the Mac hears traffic, the radio is starved, not filtered
- G7: last window hit/miss · countdown to next predicted window

### Self-describing logs
Every change and every loan start emits `[lab] config: …` — so the Mac log + watch log + config line
make each run scoreable without archaeology.

### Rails
DEBUG builds only (`#if DEBUG` around the whole view); bench banner at top; changes apply at the next
cycle, never mid-dose; every value falls back to today's shipped default when unset — absent toggles
change nothing.

---

## The experiment matrix the panel enables (one knob per run, Mac always recording)

| run | config | question it answers |
|---|---|---|
| E1 | all defaults | baseline under instrumentation |
| E2 | pod=hold-for-loan | H12 directly: does a deliberately held pod kill G7 windows (ours AND D2W's)? |
| E3 | g7=b-only (c off) | can connection-events alone sustain readings? (frees ~90% of receiver time) |
| E4 | g7=b + guard-band c | the elegant endgame: near-zero scanning, does anything degrade? |
| E5 | pod rel=0s vs 60s | does release latency move the ladder failure rate? |
| E6 | disable heartbeat probe | who re-acquires the pod every ~183 s? |

## Mockup

```swift
// RadioLabView.swift — DEBUG-only, linked from LoanDebugView
Form {
    Section("G7 acquisition") {
        Toggle("(a) Ride system link", isOn: $lab.g7RideSystemLink)
        Toggle("(b) Connection events", isOn: $lab.g7ConnectionEvents)
        Toggle("(c) Own scan", isOn: $lab.g7OwnScan)
        Toggle("(c) Guard-band ±20s", isOn: $lab.g7GuardBand)
            .disabled(!lab.g7OwnScan)
        LabeledContent("Next window", value: lab.nextWindowCountdown)   // from the exact grid
        LabeledContent("Last window", value: lab.lastWindowHitMiss)
    }
    Section("Pod link") {
        Picker("Mode", selection: $lab.podLinkMode) {
            Text("On-demand").tag(LabPodMode.onDemand)
            Text("Hold for loan").tag(LabPodMode.hold)
            Text("Hold + G7 yield").tag(LabPodMode.holdYield)
        }
        Picker("Post-dose release", selection: $lab.releaseDelay) {
            ForEach([0, 12, 60, -1], id: \.self) { Text($0 == -1 ? "Never" : "\($0)s").tag($0) }
        }
        Toggle("Heartbeat probe", isOn: $lab.heartbeatProbe)      // bisects the 180s hold
        Toggle("Alarm scan", isOn: $lab.alarmScan)
    }
    Section("Live") {
        LabeledContent("Config", value: lab.configLine)           // mirrors the [lab] log line
        LabeledContent("Pod census", value: lab.podCensus)        // adverts=N last=Ns isScanning=…
        LabeledContent("didDiscover (any)", value: "\(lab.anyDiscoverCount)")
    }
}
// Backing store: LabConfig reads UserDefaults with the SHIPPED value as fallback —
// the same pattern connectOnDemandEnabled already uses. No new persistence machinery.
```

Wiring cost estimate: the G7 toggles and pod picker are gates around existing call sites; guard-band
and hold-with-yield are the only new logic. One build, then every experiment above is a 10-second
switch instead of an install.

---

# IDEA (parked 2026-08-20) — guardrail tests for the BLE paradigm

Jeremy: *"I wonder if there is a way to write some tests that highlight risks associated with changes
in this part of the code base — like 'woah, you just changed something that matters a lot and we're
not sure why and it might break a key part of the BT paradigm, are you sure?'"*

**Why this is the right instinct.** Every BLE regression this project has suffered was a ONE-LINE
change to a condition whose importance was invisible at the site:

| the change | what broke | how long to find |
|---|---|---|
| scan armed only when `activePeripheral == nil` | 20–40 min G7 outages, D2W included | ~2 days |
| `connectionReleasedForLoan` guard, not gated to iOS | the watch refused its OWN connects | ~1 hour, 18 refusals |
| watchdog fired without checking `.connected` | 69 spurious scan restarts in a night | one night |
| `disconnectFromDevice` empties `autoConnectIDs` | advert census silently stopped counting | ~2 days (my own instrument) |

None would be caught by a normal unit test, because none is about a computed value — they are about
**invariants of radio state that only manifest against real hardware over tens of minutes.**

## What the tests would actually assert

Not "does this function return X". Rather: **paradigm invariants**, each learned the hard way and each
citing the incident that taught it.

1. **"We are never both disconnected and not scanning while we want the pod."** Fake central; drive
   the state machine through release → reclaim → connect-fail → escalate; assert scanning is armed in
   every state where a connect is pending or wanted. Catches the G7 bug's whole family.
2. **"Nothing that gates a connect is compiled into both platforms without an os() check."** The pod
   is LENT by the phone and HELD by the watch; `releaseConnection()` means opposite things on each.
   A lint/test over the guard sites.
3. **"Every connect intent reaches a terminal state."** didConnect / didFailToConnect / explicit
   cancel — assert no path can leave one open (the `pendingAdopt` + `open=0` anomaly of 2026-08-20).
4. **"An advertisement matching our pod's ADDRESS is always actionable"** — never gated on a
   collection (`autoConnectIDs`, `devices`) that a release empties.
5. **"A watchdog never fires while the thing it polices is healthy"** — assert quiet under a connected
   peripheral (the 69-firing bug).

## The "are you sure?" mechanism

Two layers, cheap first:

- **A CODEOWNERS-style tripwire**: a test that hashes the ~10 known-load-bearing conditions (the scan
  arm, the interlock guard, the adopt gate, the release path) and FAILS when one changes, with a
  message naming the incident that condition prevents and requiring the hash to be updated
  deliberately. Not correctness — *attention*. Exactly the "woah, are you sure?" Jeremy describes.
- **A fake-central harness** so invariants 1–5 can be executed rather than asserted by eye. Bigger
  build; do it only if the tripwire proves it is needed.

## Why the ship gate is not enough today
193 tests pass while every one of the regressions above shipped. They test dosing math and protocol
logic — the deterministic parts. **The radio layer has no test at all**, which is why every one of its
bugs was found on a wrist, at night, hours after it shipped.

**Status: parked idea, not scheduled.** Revisit once the current radio work settles — the invariants
should be written from what is TRUE at that point, not from a model still moving.
