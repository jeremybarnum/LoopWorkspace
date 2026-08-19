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

### H6 — watchOS throttles our scan when the app is not foreground

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
