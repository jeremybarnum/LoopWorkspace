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
| H4 | The dominant failure is DISCOVERY, not connection | classify every ladder by connects issued | **SUPPORTED, n=11** — every FAILED ladder issued ZERO connects |

H3 is real and fixed. **H4 is why fixing H3 will not fix the reclaim failures**, and saying so plainly
is the point of this table.

---

## Pre-registered for the NEXT run (build carrying the advert census)

The instruments: per-ladder advert count + RSSI (`adverts=N last=Ns rssi=X` on every ladder line), a
`** CONNECT WHILE ON LOAN **` alarm in the BLE layer, and the phone's pod-link state on its 60 s census.

### H5 — The pod is not advertising, because something still holds it

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
