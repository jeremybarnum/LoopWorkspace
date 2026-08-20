# Pod BLE — pre-registered theories, tests, and results

**Why this file exists.** Jeremy, 2026-08-19: *"keep developing the coherent model of what is actually
going on, rather than a vague series of empirical observations."* Three times in two days a theory was
argued confidently, instrumented, and killed — and each time the killing evidence arrived before the
theory had been written down precisely enough to be wrong. This file states each theory BEFORE the run
that tests it, names the observation that would falsify it, and records the verdict afterwards.

**Rule: nothing is added to the RESULT column from a run that started before the theory was written.**
A theory that only ever explains data already seen has not been tested.

---

## The null hypothesis — Jeremy's, and it is currently WINNING

> *"There should be no contention. One slot has G7, the other has the pod, they work independently, pod
> connects on demand, basically we should have no issues. The question is more about whether we have
> over-engineered something, and the result is unnecessary chaos."*

Stated as a claim: **the two radios' budgets are adequate for what we ask of them, and the observed
failures come from our own machinery — retries, escalations, central rebuilds, competing connect
paths — rather than from any physical or platform limit.**

This deserves to be the null, and as of 2026-08-19 the evidence has moved TOWARD it, not away:

- The connection ceiling is 2, we use exactly 2, and the one measured refusal mechanism was **our own
  duplicate connect** — self-inflicted (H3).
- The dominant failure does not involve connecting at all (H4) — so no slot, sensor, or airtime limit
  is implicated in it.
- `recreateCentral` rebuilds the pod central on every escalation, on a theory (H2) that has since been
  disproved — machinery whose justification is gone.

**The competing view is not "there is contention" but "there is something we do not understand about
pod visibility".** H4/H5/H6 below are attempts to find out which.

---

## Verdicts so far

| # | theory | test | verdict |
|---|---|---|---|
| H1 | The G7's near-continuous scanning starves the pod's connect | correlate reclaim outcome with G7 quiet time | **DEAD** — e132 failures span g7direct 28 s to 1254 s |
| H2 | Leaked connect intents (`recreateCentral`) exhaust the connection table | count ORPHANED; see whether Code=11 tracks it | **DEAD** — ORPHANED=1 across SUCCESSFUL connects; e132 had a refusal at ORPHANED=0 |
| H3 | Two of our own connect paths race and CoreBluetooth refuses the duplicate | do refusals coincide with two `connect via` lines in one millisecond? | **SUPPORTED, n=2** — but see H4: it happens inside ladders that SUCCEED |
| H4 | The dominant failure is DISCOVERY, not connection | classify every ladder by connects issued | **CONFIRMED** — 8/8 failed ladders heard `adverts=0 last=never` |
| H6 | watchOS throttles our scan when backgrounded | count APP BACKGROUND, not time-since-APP-FOREGROUND | **DEAD** — 0 background events during the entire ladder window; there were no background ladders |
| H5 | The pod is invisible because something still holds it | advert census + the phone's own intent ledger | **CONFIRMED — it is the PHONE**, connecting every 2–3 min while `released=true`, every connect succeeding |

H3 is real and fixed. **H4 is why fixing H3 will not fix the reclaim failures**, and saying so plainly
is the point of this table.

---

## Pre-registered for the NEXT run (build carrying the advert census)

The instruments: per-ladder advert count + RSSI (`adverts=N last=Ns rssi=X` on every ladder line), a
`** CONNECT WHILE ON LOAN **` alarm in the BLE layer, and the phone's pod-link state on its 60 s census.

### H5 — CONFIRMED 2026-08-19 16:25–16:35. **The phone connects to the pod throughout the loan.**

**This was Jeremy's hypothesis, offered as the thing he believed impossible:** *"is there any chance
that part of what's happening is that there is watch-phone contention for the pod? In my mind, that's
impossible — literally what the whole loan concept avoids."* It is not impossible. It is happening on
a 2–3 minute cadence, and it is the dominant failure.

**The phone's own intent ledger, while `released=true` for the entire window:** [MEAS]

```
16:25:47  e136 GRANT — releasing pod BLE      pod: released=false -> true    issued=3 ok=3
16:26:44  census                              pod: released=true             issued=4 ok=4   <- connect, SUCCEEDED
16:29:49  census                              pod: released=true             issued=5 ok=5   <- connect, SUCCEEDED
16:31:04  loan ABANDONED -> settle: link up +0.0s, reclaim VERIFIED +0s
16:31:21  e137 GRANT — releasing pod BLE      pod: released=true             issued=6 ok=6   <- connect
16:34:49  census                              pod: released=true             issued=7 ok=7   <- connect
```

`ok` climbs in lockstep with `issued`: every one of those connects SUCCEEDED. The phone knows it lent
the pod — `released=true` throughout — and connects anyway.

**The watch, over the same period: 8 of 8 ladders FAILED with `adverts=0 last=never rssi=-`.** Not one
advertisement in 28 seconds, eight times. A pod in a connection does not advertise, so the watch was
scanning for something that could not be heard by construction.

**And the tell we had been staring at for two days:** the phone reports `settle: link up +0.0s` the
instant the watch gives up — twice today. A cold Omnipod connect takes ~17 s. `+0.0s` was never
"the phone reconnected quickly"; it was "the phone never let go."

**What is proven, and what is not.**

- PROVEN: the phone issues successful pod connects during a loan while its own release flag is true.
- PROVEN: the watch hears zero advertisements during exactly those windows.
- STRONGLY INFERRED: the former causes the latter (a connected pod does not advertise).
- **NOT YET KNOWN: which code path on the phone is connecting.** The `via:` reason is captured in the
  `** CONNECT WHILE ON LOAN **` alarm, but `omnipodLogDeviceEvent` routes to LoopKit's device-comms
  store rather than `PhoneLog`, so on the PHONE the alarm goes somewhere unreadable. Fixing that
  routing names the mechanism in one run. It is the next thing to do.

**Why this vindicates the null hypothesis.** Jeremy: *"the question is more about whether we have
over-engineered something, and the result is unnecessary chaos."* The radios were never the problem.
Two slots, two devices, no platform limit implicated. What was missing is an interlock: **OmnipodKit
has no concept of a loan**, isolation was achieved indirectly by emptying `autoConnectIDs`/`devices`,
and any path that does not consult those collections was free to connect. It did.

---

### H5 (original statement, kept for the record) — The pod is not advertising, because something still holds it

**Claim.** A failed ladder sees `adverts=0` because the pod is connected to another central — most
likely the phone, whose release is asynchronous or incomplete. A connected BLE peripheral does not
advertise, so we are scanning for something that is by definition invisible.

**Predicts:** failed ladders show `adverts=0`; the phone's census shows a live pod link during at least
some of them; and/or `** CONNECT WHILE ON LOAN **` fires.

**Falsified by:** failed ladders showing `adverts>0` (we heard it and still failed), or the phone's
census showing `released=true` with no link throughout a failed ladder.

**Prior evidence, not proof:** on 2026-08-19 the phone reported `link up +0.0s` after 110 s of silence
during a takeover the watch was failing — a cold Omnipod connect takes ~17 s, so the link was already
up. How it got there is unrecorded. That is the hole the census fills.

### H6 — DEAD 2026-08-19. There were never any background ladders; the correlation was a measurement error.

**Jeremy killed this by challenging the premise:** *"forget about foregrounding the app. You're obsessed
with that. For the vast majority of this time I'm wrist up staring at the watch. And also, the workout
keepalive de facto foregrounds, right?"* Both halves correct.

**The measurement error.** `APP FOREGROUND` fires on `WKApplication.didBecomeActiveNotification` — a
TRANSITION, not a state sample. The analysis measured *time since the last foreground transition* and
read a long gap as "the app was backgrounded." If the app never leaves, there is no new transition, and
the gap means the OPPOSITE. The correct instrument, `APP BACKGROUND` on `didEnterBackgroundNotification`,
was logged right beside it and went unused.

**The data, once the right field was counted:** [MEAS]

| | count |
|---|---|
| `APP FOREGROUND` in the log | 50 |
| `APP BACKGROUND` in the log | **2** |
| `APP BACKGROUND` during the entire e132 ladder window (14:16–14:43) | **0** |

Every ladder classified as "background" was foreground. The 5/5-successes-had-recent-foreground vs
4/5-failures-did-not pattern was an artifact of comparing transition timestamps, not app states.

**Mechanism for why it barely exists in practice:** the loan holds an `HKWorkoutSession` keepalive
(`[keepalive] HKWorkoutSession(.other) started — background runtime ACTIVE`), which keeps the app
running, and the user is wrist-up watching the screen for most of a loan anyway.

**Kept as a lesson, not just a dead hypothesis:** two adjacent log fields, one of which answers the
question directly, and the analysis used the one that only looks like it does. Before correlating
against a derived quantity (time-since-event), check whether the state itself is logged.

---

### H6 (original statement, kept for the record) — watchOS throttles our scan when the app is not foreground

**Claim.** Background BLE scanning on watchOS delivers advertisements slowly or not at all, so ladders
that run while the user is not looking hear nothing.

**Predicts:** `adverts=0` correlates with time-since-APP-FOREGROUND, not with G7 state or ladder index.

**Falsified by:** failed ladders with a recent foreground event and `adverts=0` anyway, or successful
ladders deep in the background.

**Prior evidence, and it is WEAK:** all 5 e132 successes had a foreground event within 17–20 s; 4 of 5
failures had none for 128–430 s. **L9 breaks it** — foreground 10 s earlier, still failed. Recorded as
suggestive precisely because it does not fit cleanly.

### H7 — The pod's idle advertising interval simply exceeds the ladder budget

**Claim.** No contention and no throttling: an idle pod advertises slowly, and 28 s is not long enough
to catch one.

**Predicts:** `adverts=0` on 28 s ladders, `adverts>0` on the longer ones, and a ladder that succeeds
does so shortly after its first advert. Failure would then be a TIMEOUT choice of ours, not a fault.

**Falsified by:** any failed ladder with `adverts>0`, or short ladders that routinely hear adverts.

**This is the null hypothesis's own candidate** — it says the radios are fine and our budget is wrong.
If H7 holds, the fix is a longer or advert-driven ladder, not more machinery.

---

### H8 — PRE-REGISTERED 2026-08-19, BEFORE the phone-off arm. **Turning the phone off frees the pod.**

This is the intervention test of H5. H5 was observational — we watched the phone connect and watched
the watch hear nothing. H8 removes the proposed cause and predicts the effect disappears. If H5 is
right, this is the strongest confirmation available without touching a line of code.

**Claim.** The phone's periodic connects are what keep the pod from advertising. Power the phone off and
the pod is uncontested: it advertises, the watch hears it, and reclaims succeed.

**Predicts, in order of how diagnostic each is:**

1. **`adverts>0` on every ladder**, and quickly — an idle Omnipod advertises far faster than once per
   28 s, so a freed pod should be heard within seconds, with a real RSSI (both devices are on the same
   body, so expect a strong one).
2. **Ladders SUCCEED**, and fast — the ones that worked earlier today ran 0–18 s, against the uniform
   28 s timeouts of the failures.
3. **The failure rate collapses.** Baseline for comparison: **8 of 8 ladders failed** in the phone-on
   arm, every one at `adverts=0 last=never`.

**Falsified by:**

- **`adverts=0` persisting with the phone off.** This is the important falsifier. It would mean the
  phone is not the mechanism — or not the only one — and would revive H6 (watchOS throttling our
  background scan), which the phone-on data cannot currently distinguish from H5.
- **`adverts>0` but ladders still failing.** A different bug entirely: we hear the pod and cannot
  connect to it. Nothing so far predicts this, which is what makes it worth watching for.

**Confounders, named in advance so they are not discovered afterwards:**

- **The sensor's collector count drops 3 → 2** (phone + D2W + Sport Mode becomes D2W + Sport Mode). If
  G7 behaviour also improves, that is a SECOND effect of the same action and must not be credited to
  the pod story. Watch `g7direct` separately.
- **The log mirror dies with the phone.** The watch relays its log via WCSession to the phone, so a
  phone that is off is exactly what stops the record — the reason `ops/watch-logs-pull.sh` exists.
  Plan the retrieval BEFORE switching off (see protocol below).
- **No dead-man reclaim while the phone is off.** If the watch fails, nothing takes the pod back until
  the phone returns. Acceptable on the bench rig; would not be acceptable otherwise.

**Record:** the exact minute the phone goes off, and the exact minute it comes back.

---

### H9 — PRE-REGISTERED 2026-08-19 ~17:15, BEFORE the data. **Why does Dexcom drop 10–20 min after the phone is powered off?**

**The observation.** 2026-08-19: phone off at 17:01; at ~17:11 Loop's own status was unchanged and
healthy while the DEXCOM watch app reported signal loss. Jeremy reports recognising this pattern from
previous sessions, including that **it heals itself in 10–20 minutes**.

**Why it matters commercially, not just diagnostically.** Jeremy: *"for someone doing 1 hour of
exercise immediately after shutting down the phone, it's a bit of a bummer."* Phone-off exercise is the
product's core use case. A 10–20 minute CGM gap at the start of it is not an edge case.

**Priors, recorded BEFORE the data — Jeremy's, since this is his observation and his device history:**

| candidate | Jeremy | mine (after the code check below) |
|---|---|---|
| **(2) Collector-slot bookkeeping** — an abrupt power-off never gracefully tears down the phone's link, so the sensor holds that collector reserved until it times out. 10–20 min ≈ 2–4 sensor windows. | **40%** | 40% |
| **(4) Coincidence** — sensors drop out on their own | **35%** | 30% |
| **(1) Not a radio event** — D2W renders a phone-dependent state as "signal loss" | ~5% | 5% |
| **(3) We squeeze D2W** — our G7 path works harder with the phone gone | ~5% | **2%** |
| **Something else not yet imagined** | **20%** | 23% |

**(3) is all but eliminated by code, not by argument.** `G7SensorKit` never consults phone
reachability — there is no such branch anywhere in it, and the only `reachable` reference in the entire
watch extension is an error log on a glucose-backfill request. There is no "work harder when the phone
is away" path to invoke. Jeremy called this implausible on instinct; the code agrees.

**The test, and it needs no new instrumentation.** Our G7 stack already records the OS telling us when
D2W connects:

```
[g7-ble] connection-event CONNECT DXCMqL — ignored, have active
```

So D2W's own connection cadence is visible in OUR log. Extract it across the 17:01 boundary:

- **D2W connect events CONTINUE at the normal ~5 min rhythm through the reported outage** → (1). The
  sensor was fine and the message is about the phone. Cheapest to check, so check it first.
- **D2W connect events STOP at/after 17:01 and resume ~10–20 min later, while OUR readings continue
  uninterrupted** → (2). Our collector slot was never disturbed; D2W's was, which is what a stale
  reserved slot would do.
- **BOTH stop** → not a collector-allocation story at all; the sensor itself went quiet. Points at (4)
  or the unknown 20%.
- **Our own scan/connect rate visibly rises after 17:01** → (3), and the code reading above is wrong.

**Falsifier for the whole frame:** if D2W's cadence is unchanged across the boundary in a session where
Jeremy observed the outage, then the outage is not a connection phenomenon and every candidate above is
mis-specified.

#### H9a — the RECOVERY CONSTANT, and the sharper test it implies

Jeremy, from experience across sessions: *"these things tend to cure themselves within 25–30 minutes.
That's the same as the 28 minute sensor warmup thing. Not sure if this is cargo cult."*

Two halves, and they are not equally good evidence.

**The warmup link is probably a coincidence of numbers.** Warmup is a session-START process — sensor
chemistry settling, algorithm calibrating — while this is a collector re-establishing a link to an
already-running sensor. Different lifecycle stages, no obvious shared timer. Not disprovable from
outside Dexcom's firmware, but no reason to expect it either.

**The recurrence of the constant is the real signal, because we have already recorded it for a
DIFFERENT disturbance.** A standing note in this project holds that the G7 self-recovers ~25 minutes
after a **pod takeover** — nothing to do with the phone. [Provenance: standing note carried into this
session, NOT re-verified in this tree. Confirm against the pure branch's field observations before
leaning on it.]

Same ~25 minute constant, two unrelated causes. **That is what makes coincidence unlikely** and points
at a single timeout downstream of both — most plausibly the sensor's own collector bookkeeping, which
is candidate (2).

**PRE-REGISTERED PREDICTION.** If it is a fixed timeout:

> Recovery time is roughly CONSTANT — independent of what caused the disturbance and of how long the
> disturbance lasted. A 2-minute phone-off and a 40-minute phone-off should both heal ~25 minutes after
> the DISTURBANCE, not ~25 minutes after the RESTORATION.

**Discriminates hard:**

- **Constant recovery regardless of disturbance length** → a fixed timeout. Near-conclusive for (2).
- **Recovery scaling with disturbance length** → not a timeout; something proportional, e.g. a backoff
  that grows while the condition persists.
- **Recovery timed from RESTORATION rather than from disturbance** → the healing is triggered by the
  phone's return, which would make it a re-negotiation on reconnect, not a lapsed reservation.
- **Recovery varying randomly** → coincidence, candidate (4), Jeremy's 35%.

**Cheapest next experiment:** a SHORT phone-off — two or three minutes — and time the recovery from the
moment of power-off. Costs almost nothing and splits the four branches above in a single run.

#### H9a RESULT — 2026-08-19. Recovery is a TIMEOUT, not a re-negotiation. [MEAS]

| event | wall clock | elapsed from power-off | sensor windows |
|---|---|---|---|
| phone powered off (disturbance) | 17:01:00 | 0 | 0 |
| Dexcom reports signal loss | ~17:11 | ~10 min | **2** |
| Dexcom recovers | 17:25 | **24 min** | **~5** |

**The phone was still off at recovery.** That is the whole result: the outage healed with the proposed
cause still absent, so healing is NOT triggered by the phone's return. The "recovery timed from
RESTORATION" branch is dead, and the fixed-timeout branch is supported — pre-registered before the run,
and it discriminated.

24 minutes against Jeremy's remembered 25–30, from experience across earlier sessions.

**Everything is quantized to the sensor's 5-minute grid**, which is itself evidence. Two windows before
the UI declares a loss is what a display that does not want to alarm on a single miss would do; a
~5-window reservation lapse is a plausible round number in firmware. Nothing lands at an odd interval,
which fits a DESIGNED timeout rather than an emergent contention effect.

**Still open:** the mechanism is inferred, not observed. The D2W connection cadence in our own watch log
across 17:01–17:25 is the direct evidence and has not been read yet — it will show whether D2W's
connect events actually stopped, and whether OUR readings continued through the same window.

#### H9 RESULT — 2026-08-19/20 FARADAY ARM. **Unreachability does NOT reproduce it. H9 is mis-specified.**

**The arm.** Phone into a faraday cage at 23:44:28 with a healthy loan running — powered on, BLE alive,
simply unreachable. No shutdown, no reboot. The closest controlled analogue of the swimming case.

**The Mac observer, which is neither collector:** [MEAS]

```
23:41:37  ADV G7  gap=295.8s     <- last before the cage
23:44:28  ---- phone into faraday cage ----
23:46:36  ADV G7  gap=293.1s     OK
23:51:38  ADV G7  gap=297.8s     OK
23:56:37  ADV G7  gap=293.8s     OK
00:01:36  ADV G7  gap=295.4s     OK
```

**Four consecutive windows, every one within 5 s of the exact 300 s grid.** The sensor did not react in
any way to a bonded collector vanishing.

**And the watch kept looping GREEN throughout** — no G7 staleness, no outage. So the phenomenon did not
reproduce at all.

**What this kills.** Both branches of H9 as written. Not the "sensor shock" story (the sensor was
serene), and not the collector-slot story either — because nothing went wrong to explain. Jeremy also
notes **overnight phone-OFF runs have looped cleanly**, which independently rules out phone absence as
a sufficient trigger.

**So the 2026-08-19 17:01 event — both collectors dark for 22 minutes, 36 s after power-off — remains
UNEXPLAINED, and its correlation with the power-off is now suspect.** One co-occurrence plus a
remembered pattern is not a mechanism, and the controlled test says absence is not it.

**What is still solid from that night:** the recovery was a TIMEOUT not a re-negotiation (healed with
the phone still gone, H9a), and the durations were quantized to the sensor's 5-minute grid. Those
describe the SHAPE of the event. Its TRIGGER is unknown.

**Next time it happens** — and it will, per Jeremy's history — the Mac observer is now the instrument
that settles it in one reading: sensor transmitting through the outage means collector-side and
fixable; sensor silent means something we have never seen. Leave it running.

#### H9b — Dexcom's OWN remedy is a Bluetooth toggle, and its stated wait is HALF the natural heal

Jeremy, 2026-08-19: *"the Dexcom app recommends toggling bluetooth and waiting 10 minutes in response
to sensor failure."*

**Two things follow, and the second is a real prediction.**

**(i) BT toggle is now the universal remedy across three unrelated symptoms in this project:**

| symptom | remedy | source |
|---|---|---|
| pod unreachable from BOTH devices after hand-back | BT toggle | field-proven 2026-08-19 |
| watch not appearing for `devicectl` discovery | BT toggle | field 2026-08-19 |
| **Dexcom sensor signal loss** | **BT toggle** | **Dexcom's own app** |

Three failures that look unrelated, one remedy, and one of them prescribed by the hardware vendor. That
is convergent evidence the shared state is connection-table / registration bookkeeping at the OS or
controller level, not anything specific to our code. It also means the BT toggle is not folk remedy in
ANY of the three cases — the vendor ships it as the documented fix.

**(ii) The DURATIONS differ, and that is the testable part.** Dexcom says wait **10 minutes** after a
toggle. Jeremy's observed natural heal, with no intervention, is **25–30 minutes**.

> **PREDICTION: the BT toggle roughly HALVES the recovery.** If the toggle is merely a placebo that
> fills the wait, both numbers should be the same. They are not.

Two reproducible durations for the same end state is hard for candidate (4) — coincidence does not
predict a shorter number under a specific intervention. It fits (2) cleanly: a stale reservation that
either EXPIRES on its own (~25 min) or is CLEARED by resetting the connection table (~10 min).

**Test:** next time the outage appears, toggle Bluetooth immediately and time the recovery from the
toggle. ~10 min supports (2) strongly; ~25 min from the original disturbance regardless means the
toggle does nothing and the vendor's advice is itself cargo cult; anything else is new information.

**Note the asymmetry worth thinking about:** the stale collector slot, if that is what this is, would be
held by the SENSOR on behalf of the dead phone. A toggle on the WATCH does not obviously free it — so
if the toggle works, the mechanism is more likely that it forces D2W to re-negotiate and the sensor
evicts the stale entry on demand. That distinction matters, because only one of those two stories
predicts the toggle helping when done on a device that was never the one that vanished.

---

## Run protocol — conditions that invalidate a run

- **No builds during a loan.** Installing replaces the watch app and kills it mid-loan; the phone then
  reclaims via the dead-man path. That is a different experiment (and on 2026-08-19 it completed in
  ~30 s from cold, which is the dead-man working), but it is not the one being run, and any ladder
  data after it belongs to a killed process.
- **`appInstalled=true` on the phone before starting**, or ack delivery queues and the hand-back wedges
  on "returning records" regardless of anything under test.
- **Note loan start and end times.** Ladder numbering restarts per epoch; without boundaries the
  early-vs-late arc cannot be read.
- **Record whether the phone is on or off**, since it changes the sensor's collector count (3 vs 2) and
  removes the phone as a competitor for the pod at the same time — two variables, always moving
  together.

---

## Settled 2026-08-19 16:23 — what `appInstalled` actually tracks

Not a pod theory, but it gates every run, and a wrong story about it cost most of an afternoon.

**The transition, caught the first time the instrument existed:**

```
16:23:28.168  ** WATCH STATE CHANGED ** paired=true appInstalled=true reachable=true activation=2 complication=true
```

**`WCSession.isWatchAppInstalled` is SYSTEM state, not app state.** It reads false while a freshly
installed watch app is not yet registered as the companion, and true once registration completes. The
phone app only needs to be RUNNING to observe it.

Two things that were believed and are wrong:

- **"Install order determines it."** Proposed on a single 13:41:42 observation (watch install, then
  phone install → true). Refuted the same afternoon: the same order produced `false` at 16:18, and the
  eventual flip at 16:23:28 came with the opposite order. Ordering matters only in that the phone app
  must be running to see the change.
- **"Force-quitting the apps will resolve it."** It cannot. Both apps were force-quit and reopened at
  ~16:19 with no effect, because the flag is not owned by either app.

**Why it gates the experiment:** with `appInstalled=false`, WCSession QUEUES every message instead of
delivering it. The hand-back ack never lands, so the watch spins on "returning records" forever while
the phone has already taken the pod back in a second. Any ladder data from such a run is measuring a
broken transport, not the radio. Hence the protocol precondition above.

**The lesson that generalises:** a level sampled every 60 s cannot be attributed to an event. The
delegate callback that fires ON the change existed in WCSessionDelegate the whole time and was simply
not implemented. Before theorising about what causes a flag to change, check whether the platform will
just tell you.

---

## How the framework has evolved

1. **Airtime → connection table.** H1 assumed the radio was the scarce thing. It is not; an established
   link is nearly free and scanning is what costs.
2. **Connection table → our own code.** H2 assumed the platform was leaking our slots. It is not; the
   ceiling is documented (2) and we sit exactly at it, but the one refusal mechanism found was our own
   duplicate connect (H3).
3. **Connecting → discovering.** H4 is the real break. Every framing before it was about the moment we
   ask for a link. The failures happen a stage earlier: there is nothing there to ask.
4. **Therefore the question changed** from "why are we refused?" to **"why is the pod invisible?"** —
   and H5/H6/H7 are the three ways that can happen: something holds it, we cannot hear it, or it is not
   talking yet.

Note the direction of travel: each step has moved responsibility from the platform toward our own
design, which is what makes Jeremy's over-engineering null the live one rather than a rhetorical foil.

---

### H10 — PRE-REGISTERED 2026-08-20 00:40, BEFORE the run. **Does our own G7 stack going live break pod reception?**

**The observation to explain.** In loan e141 the boundary was exact:

```
23:40:25  temp ACCEPTED by pod · CYCLE VERDICT enact=ok     <- last success
23:41:37  [g7-ble] didConnect DXCMqL                        <- G7's FIRST connection of the session
23:42:03  enact=FAILED                                      <- and every cycle for the next 27 min
```

Before: ladders OK at `adverts=9`, bolus delivered, temp accepted. After: `adverts=0` on all 11
remaining ladders, while the Mac observer heard the pod 7-15 times in each of those same windows.

**Claim.** Two `CBCentralManager`s in one watchOS process (`G7SensorKit` + `OmnipodKit`). Once the G7
central is actively working, the pod central stops RECEIVING advertisements — not refused connects, not
a silent pod, but `didDiscover` callbacks that never arrive for traffic provably in the air.

**The arm (Jeremy's design).** Start a loan, isolate the PHONE's radios, wait for G7 to go live on the
watch, then attempt a manual bolus. Isolating the phone removes the only remaining confound: if the
bolus fails anyway, the phone is exonerated for the third time and the cause is inside the watch.

**Predicts:**
- Bolus ladder FAILS with `adverts=0` while the Mac hears the pod in the same window → **H10 supported**;
  the fix is watch-internal (scan arbitration between our two centrals).
- Bolus SUCCEEDS with `adverts>0` → **H10 dead**; the e141 boundary was coincidence and G7-live is not
  the trigger.

**Falsifier already on record, and it matters.** The 2026-08-19 afternoon phone-off successes (L12, L17,
L19) ran at `g7direct=5-31s` — G7 recently ACTIVE — and succeeded. So "G7 alive => pod deaf" is NOT a
universal law; something modulates it. A single success in this arm therefore does not confirm H10, and
a single failure does not prove it. **What is being tested is whether the e141 boundary reproduces.**

**Record:** the minute the phone's radios go off, the minute G7 first connects on the watch, and the
minute of the bolus attempt.

#### H10 RESULT — 2026-08-20 00:22. **DEAD, by its own pre-registered falsifier.**

The arm ran with the phone's radios OFF, so the phone is exonerated for the third time. [MEAS]

```
00:18:05  phone radios OFF
00:20:52  pod's last advertisement (MAC) — pod FREE, rssi -56..-62, every few seconds
00:20:57  bolus attempted -> HANGS          <- G7 NOT yet direct
00:21:40  G7 goes direct on the watch
00:22:38  pod still silent = HELD by the watch
~00:22    second bolus -> SUCCEEDS          <- G7 LIVE
```

**H10 predicted the opposite in both halves.** It said pod comms work before the G7 connects and break
after. What happened: the bolus HUNG before the G7 was live, and SUCCEEDED after. The registered
falsifier ("bolus SUCCEEDS with adverts>0 => H10 dead") fired exactly as written.

**So the e141 boundary (23:41:37 G7 connect, failures from 23:42:03) was COINCIDENCE.** Two
`CBCentralManager`s in one process is not the mechanism. That is 2026-08-18's H1 dead for the second
time, on better evidence.

### What survives, and it is worth stating plainly

1. **The receive failure is REAL and is the root cause.** Independently confirmed twice: the Mac heard
   the pod 7-15 times per window during e141's failed ladders, and again at 00:20:52 — five seconds
   before a bolus hung — at -56 dBm.
2. **The phone is not the cause.** Three separate exonerations now: the faraday window, the caged
   ladders L6-L11, and this radios-off arm.
3. **It is INTERMITTENT and SELF-RESOLVING.** The pod became reachable ~90 s after the hung attempt,
   with no intervention. e141's ladders failed for 27 minutes; here it cleared in ~90 seconds.
4. **Every structural theory is now dead** — G7 scan contention, connection-slot exhaustion, leaked
   intents, duplicate connects, phone contention, two-central starvation. What is left is a
   PROBABILISTIC acquisition failure whose trigger nothing so far predicts.

### Where to look next, given everything above is eliminated

The remaining candidates are all about the SCAN ITSELF rather than about who else is on the radio:

- **Is our pod scan actually running when a ladder fails?** Log `centralManager.isScanning` at every
  failed read. Nobody has checked whether the scan is armed at all.
- **Is the central deaf, or mis-filtered?** Log EVERY `didDiscover` regardless of service filter. If
  the central sees zero peripherals of any kind while the Mac sees traffic, it is starved; if it sees
  others but not the pod, the filter or the pod's advertised services are the issue.
- **Does a scan restart clear it?** The self-resolution after ~90 s is suspicious: something re-armed.
  Finding what re-armed is likely to name the fix.

---

### H11 — PRE-REGISTERED 2026-08-20 00:29, BEFORE the confirming data. **Holding one link deafens the scan for the other.**

**Claim.** The watch can HOLD a BLE connection or RECEIVE advertisements, but not both well. Whichever
link is currently held, the other stack's scan stops getting `didDiscover` callbacks for traffic that
is provably in the air.

**Why this and not H10.** H10 said two centrals SCANNING starve each other, and died: the bolus
succeeded with the G7 live. H11 says the conflict is between HOLDING and SCANNING — a different
mechanism using the same two stacks, and it is not touched by H10's falsifier.

**The observations it was built from (both [MEAS], both independently corroborated by the Mac):**

| when | pod link | G7 outcome |
|---|---|---|
| e141 23:42–00:07 | NOT held (11 ladders failing) | **fine** — readings at `g7direct=28s, 56s` |
| 2026-08-20 from 00:25:22 | **HELD** (pod silent on the Mac = watch has it) | **missed 00:26:37 window, then went STALE** |

And symmetrically, from the pod side: during e141's failures the Mac heard the pod 7-15 times per
28-second window while the watch heard **zero** — a scan deaf to traffic at -56 dBm.

**Predicts:**
1. **G7 window misses cluster inside pod-held intervals.** Testable RETROSPECTIVELY from data already
   captured: pod-silence intervals come from the Mac, G7 ingest times from the watch log.
2. Pod ladder failures cluster inside G7-connected intervals (the ~11 s window per 5 min).
3. Both failures should END when the competing link drops — which matches the observed
   self-resolution (e141: 27 min; 2026-08-20: ~90 s) without anyone intervening.

**Falsified by:**
- G7 misses distributed evenly with respect to pod-held intervals.
- Any sustained period with BOTH a held pod link AND on-time G7 windows.
- e141's counter-case standing up: ladders there failed for 27 minutes while the pod was NOT held and
  the G7 was working — under H11 the pod scan should have been fine in that window. **This is the
  strongest thing against H11 and must be explained or it dies.**

**Status: candidate only.** n=1 on the G7 side. The retrospective test on tonight's logs is the first
real evidence either way and requires no new run.

---

### H12 — PRE-REGISTERED 2026-08-20 01:05. **A held connection starves the WATCH's scanning device-wide.**

**Claim.** When the watch holds a BLE connection (tonight: the pod, held ~180 s of every ~183 s), the
watch's advertisement RECEPTION degrades across the whole device — our pod scan, our G7 scan, AND
Dexcom's own D2W app. Not a two-centrals-in-one-process effect (that was H10, dead); a device-level
scheduling effect.

**The observation that forced it:** during the 00:22–00:57 G7 outage, D2W — a separate process with
its own central — reported no signal at the same time as our stack, while the Mac recorded the sensor
transmitting on grid the entire time (every burst 00:21:36 → 00:56:37 present, gaps 293–298 s). Both
collectors deaf, sensor innocent, pod held ~99% throughout.

**Predicts:** reception recovers when the held link drops. G7 window hit-rate should track pod-FREE
intervals; the outage should end within ~1–2 windows of a sustained release.

**Falsified by:** a sustained held-pod period with normal G7 hits (counter-example already on file:
00:21:40 landed while held — n=1 against), or an outage persisting through a sustained pod-free period.

**Note on the recovery just observed (~00:57–01:05, "late but not that late"):** the pod's last advert
before recovery was 00:55:32 — a free gap — and the 00:56:37 burst was the first after it. Whether the
CATCH coincided with a free interval needs the watch log (radios still off when this was written).
Scored when the mirror lands.

**Branch caveat (Jeremy's correction, accepted):** next-dev changed BOTH the G7 stack and the pod
stack relative to pure, so nothing here attributes to either alone. Pure may or may not exhibit this;
that is an open empirical question, not an inference.

#### H12 STATUS — wounded at birth, by Jeremy's question and the Mac's own boundaries

*"If it's all about held connections, then why would it get salvaged?"* — the outage is TIME-BOUNDED
(20–40 min, self-healing) while the hold cycle runs unchanged through recovery. And both boundary
catches (00:21:40, 00:56:37) landed WHILE the pod was held; e141's deaf period ran while the pod was
FREE. Held-state discriminates nothing. A static cause cannot produce a bounded outage.

### H13 — PRE-REGISTERED 2026-08-20 01:15, BEFORE the watch log lands. **G7 ride-teardown wedges reception; a ~20–40 min timer clears it.**

**Claim.** Completing a G7 connection ride leaves the watch's advertisement reception wedged —
device-wide, D2W included — and something with a ~20–40 minute period un-wedges it.

**The cross-event invariant it rests on:** deafness began immediately after a G7 didConnect in all
three observed events (23:41:37→e141's pod deafness ~27 min; 00:21:40→tonight's G7 deafness ~35 min;
17:01:36 ride→the 22.6 min outage). Pod hold state differed across them; the ride did not.

**Whose timer — the discriminating read, from the 00:22–00:57 watch log when it mirrors:**
- A rebuild/re-arm line (watchdog, stack recycle, scan restart) at ~00:56 → **OURS**; fix = run it
  sooner or fix the wedge it clears.
- `scan STARTED` armed throughout, zero deliveries, nothing at the recovery moment → **watchOS
  internal expiry**; matches the BT-toggle remedy (a manual expiry) and Dexcom's 10-minute advice;
  fix = avoid the wedge, i.e. change ride teardown.

**Falsified by:** a deafness onset with no preceding G7 ride, or a recovery provably triggered by
something else (e.g. app relaunch), or the 00:22–00:57 log showing normal didDiscover delivery (which
would mean the watch heard and dropped higher up).
