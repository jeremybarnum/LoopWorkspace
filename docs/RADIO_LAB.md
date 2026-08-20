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
