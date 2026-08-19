# UX nice-to-haves — first-experience and polish backlog

Started 2026-08-19 at Jeremy's request: *"we should start a UX list of nice to haves... so that
people's first experience is good."*

**What belongs here:** small, low-risk interaction changes that make the product feel finished. None of
these is a safety issue and none should derail current work — the point of writing them down is so they
can be batched later instead of interrupting now.

**What does NOT belong here:** anything on the dosing path, anything that changes radio behaviour, and
anything that is actually a bug with a therapy consequence. Those go to the field notes or the
pre-registration doc.

Each entry says what the user sees, why it happens, and a candidate fix — with the cost named, because
several of these trade against radio budget and that trade is Jeremy's call, not a detail.

---

## 1. The first loan after an install is slow

**Seen:** repeatedly, 2026-08-19. A takeover minutes after a fresh install takes far longer than the
steady-state ones that follow. One measured case ran 110.9 s and failed outright; the retry 67 s later
connected in ~1.5 s.

**Why:** at launch the pod link is cold — no peripheral handle, nothing in `autoConnectIDs` that has
been exercised, no recent advertisement heard. The first takeover pays the whole acquisition cost while
the user is watching, which is the worst possible moment for it.

**Candidate: pre-warm.** On app launch (or on entering the glance), arm the pod scan and adopt the pod
if it is heard — before any loan is requested. By the time the user asks, the link is warm.

**Cost, stated honestly:** this spends radio time on a loan that may never be requested, and the pod is
one of two connection slots. Pre-warming while the G7 is establishing is exactly the collision we spend
the rest of our time trying to avoid. A cheap version — arm the SCAN but do not connect — costs much
less and may capture most of the benefit, since the measured failure mode is discovery, not connection.

**Do not build until:** the discovery question (H5/H6/H7 in `POD_BLE_PREREGISTRATION.md`) is settled.
If watchOS throttles background scanning, a pre-warm arms a scan that hears nothing and buys nothing.

---

## 2. "No G7" at loan start reads as a fault, and is not one

**Seen:** 2026-08-19. At takeover the CGM panel showed *sensor none, connection never, link scanning,
state searching* — while Dexcom's own app was working perfectly. It resolved by itself.

**Why:** the sensor transmits on an exact 5-minute grid. A cold start lands at a random point in that
cycle, so the first reading can be nearly five minutes away. Nothing is wrong.

**Candidate:** say what is actually true — *"waiting for the next sensor window"*, ideally with the
countdown, since the grid is exact and one reading anchors it. "None / never / searching" describes a
broken sensor; this is a sensor working normally, observed early.

**Cost:** none. Text and a computed countdown.

---

## 3. The watch spins on "returning records" forever when the phone already owns the pod

**Seen:** 2026-08-19 13:00. The hand-back SUCCEEDED — the phone committed and verified a pod round-trip
in one second — and the watch spun until it died, re-offering every 15 s for twenty minutes.

**Why:** the ack could not be delivered (`appInstalled=false` queued it), and there is no ceiling on the
returning state.

**Candidate:** a bound on the state. After N unacked re-offers, stop and say *"the phone has the pod"* —
which is both true and reassuring. Nothing is at risk when this happens; it merely looks exactly like
the state where something is.

**Cost:** none. This one is worth doing regardless of the transport bug, because a UI that cannot say
"you are fine" during a state that IS fine is a UI that manufactures alarm.

---

## 4. The glance freezes while a reclaim ladder runs

**Seen:** 2026-08-18. Six `[loop] OPENED by user` events inside one second — the user tapping because
nothing responded. Every tap had registered.

**Why:** the glance ticks on the loan controller's serial queue, which the pod ladder holds for up to
28 s.

**Candidate:** let the glance read a snapshot rather than taking the queue.

**Cost:** small, real work. Worth it independently of the radio fixes — *a display that cannot repaint
while the radio is busy is a display that fails exactly when it is being watched.*

---

## 5. Tapping "closed loop" to open it gives no feedback

**Seen:** 2026-08-19, Jeremy: *"clicking on closed loop in order to open it doesn't give any response
although it eventually works."*

**Why:** almost certainly item 4 wearing a different hat — the state changes on the first tap, the
screen just cannot say so.

**Candidate:** immediate optimistic feedback on tap, reconciled when the state actually lands.

---

## 6. Insulin is displayed to three decimal places

**Seen:** everywhere insulin is shown — `IOB 1.427 U`.

**Why:** `QuantityFormatter(for: .internationalUnit)` has `maxFractionDigits = 3`. Pod granularity is
0.05 U, so the last two digits assert precision the hardware does not have.

**Status:** fixed on the watch by rounding at source; the phone side is upstream. See
`UPSTREAM_PR_CANDIDATES.md` #2.

---

## 7. Surface the Bluetooth-toggle recovery to the user

**Seen:** 2026-08-19, twice. With the pod unreachable from both devices, toggling Bluetooth off and on
recovered it — the only thing that did.

**Candidate:** put it in the stuck-settle alert text. It is a one-tap recovery for a state that
otherwise looks like a lost pod, and a user who does not know it will assume the worst.

**Cost:** none, and the fit between the remedy and the diagnosis is good: a BT toggle resets the
connection table, which is the resource the failure implicates.
