# The BLE configuration space — the choices we actually have

Written 2026-08-20 01:00, at Jeremy's request: *"it feels like we need to go back to our model of the
BT connection. One device, two devices, G7 a/b/c mode, and G7 preference and pod 'on demand' vs full
teardown."*

**Why this file exists.** Eleven hypotheses were registered over two days (H1–H11) and most are dead.
That is hypothesis whack-a-mole: each one explained the last observation and was killed by the next.
The failure was never enumerating the DESIGN SPACE — the handful of real knobs, what each costs, and
which combinations have actually been measured. This is that enumeration. It is deliberately about
CHOICES, not theories.

---

## The five dimensions

### 1. Device topology — one device or two

| | what it is | status |
|---|---|---|
| **Two-device** | phone owns the pod, lends it to the watch for a session | pure, next-dev (current) |
| **One-device** | the watch owns the pod outright | crude |

**Crucially, this does NOT change how many BLE stacks run on the WATCH.** Crude ran its own G7 client
AND the pod on the watch, and the standing note from that era says the G7 client "delivered 0/103
readings yet is what blocks the pod." **Same contention, before the two-device design existed.**

So: going back to one device does not buy an exit from the radio problem. It changes ownership and
hand-back complexity, not the number of radios competing on the wrist. [Provenance: standing note,
not re-verified in this tree.]

### 2. G7 acquisition trigger — a / b / c

Named in `G7BluetoothManager` and visible in the census:

| trigger | mechanism | cost |
|---|---|---|
| **(a)** | `retrieveConnectedPeripherals` at scan start — ride a link the system already holds | free |
| **(b)** | `connectionEventDidOccur` — the OS tells us a sensor-service peripheral connected (in practice, D2W) | free; no receiver time |
| **(c)** | our own scan hears the advertisement | expensive — this is the ~270 s/window scan |

**Measured 2026-08-19:** the sensor advertises in a **~4-second burst every 300.0 s** — a 1.3% duty
cycle, on a grid exact to a part in 84,000. So (c) currently scans ~270 s to catch a 4 s event whose
time we can predict to under a second. **Jeremy's stated bias: strongly prefer (b).**

### 3. Pod link mode — on-demand vs standing vs teardown

| mode | what it does | knob |
|---|---|---|
| **connect-on-demand** | pod left disconnected between commands, connected per dose | `connectOnDemandEnabled` (default TRUE) |
| **standing connection** | hold the link for the session | `shouldHoldConnection` |
| **full teardown** | drop the central entirely | `recreateCentral()` (escalation path) |

**The startup log claims:** *"link policy AUTOMATIC (#101): pod orphaned between doses, reclaim per
cycle."*

**What was MEASURED tonight (2026-08-20 00:25–00:41), from the Mac:**

```
held ~183s -> released 00:28:25    held ~180s -> released 00:31:26
held ~179s -> released 00:34:24    held ~182s -> released 00:37:28
held ~181s -> released 00:40:31
```

**The pod is held ~180 s out of every ~183 s — roughly 99% of the time.** That is a standing
connection in all but name, and it contradicts the policy the app prints about itself. **This is the
single most surprising measurement of the night and nobody has explained it.** Either the release is
not firing, or something re-acquires immediately, or the policy description is simply wrong.

### 4. G7 preference — who yields to whom

Currently: **nothing.** `StockLoopSession` says so explicitly — *"NO RADIO ARBITER, deliberately"* —
because the arbiter's only signal producer was removed with the old G7 reader. So there is no
scheduling between the two stacks at all; they collide or don't by luck.

Options never implemented: pod yields during the predicted G7 window (computable to the second, since
the grid is exact); G7 yields during a dose; strict priority either way.

### 5. Radio topology on the watch — the constant nobody chose

Two `CBCentralManager`s in one process (`G7SensorKit`, `OmnipodKit`), against a documented watchOS
ceiling of **two simultaneous connections per app**. We therefore run permanently at 100% of the
connection budget with zero headroom, in every configuration above, including crude.

---

## What has actually been MEASURED, against what is assumed

| claim | status |
|---|---|
| Sensor advertises 4 s per 300 s, grid exact | **MEASURED** (Mac, 550+ bursts) |
| Pod advertises continuously when free (gaps 0–8 s) | **MEASURED** (Mac, 3400+ adverts) |
| Watch fails to receive adverts that are provably in the air | **MEASURED** twice (Mac heard 7–15/window; watch heard 0) |
| Phone contention causes the failures | **REFUTED** three times (faraday, caged ladders, radios-off) |
| Two centrals SCANNING starve each other | **REFUTED** (bolus succeeded with G7 live) |
| Holding one link deafens the other's scan | **counter-example exists** (G7 landed 00:21:40 while pod held) |
| Pod held ~99% during a loan | **MEASURED**, and contradicts the stated policy |
| Loop stalls ~19 min when G7 is starved | **MEASURED** (last loop 1121 s at 00:41) |

---

## The experiment that follows from the space, not from a hypothesis

The knobs are few and independently settable. Rather than another theory, vary one at a time and
measure ladder success + G7 window hit-rate, with the Mac recording throughout:

1. **Fix the pod hold first.** It is measured, it contradicts the documented policy, and it plausibly
   starves everything downstream. Until the pod actually orphans between doses, every other
   measurement is taken in an unintended configuration. **Highest priority — this is a bug, not a
   design choice.**
2. **G7 trigger (b) only** — disable the (c) scan entirely and see whether readings survive on
   connection-events alone. Frees ~90% of receiver time if it works.
3. **Guard-band (c)** — scan only ±15 s around the predicted window instead of ~270 s.
4. **Explicit arbitration** — pod yields during the predicted G7 burst. Only worth building after 1–3,
   and only if collisions remain.

**The discipline this file is meant to enforce:** each run changes ONE knob, states the expected effect
first, and is scored against the Mac's independent record. Eleven dead hypotheses are what happens
without that.
