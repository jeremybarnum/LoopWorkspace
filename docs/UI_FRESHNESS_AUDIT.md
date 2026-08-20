# UI freshness audit — what each element measures, and which ones lie

Written 2026-08-20 at Jeremy's request, ahead of sharing the branch: *"loops will fail, and I need to
make sure that the UI behaves reasonably when the loop gets stale."*

**The principle being audited:** every number on the glance should either be current, or visibly say it
is not. A screen that looks healthy while dosing has stopped is worse than one that looks broken.

---

## What each element actually tracks

| element | measures | truthful when the loop fails? |
|---|---|---|
| **Ring** (`loopFreshness`, GlanceView:645) | **BG recency** — `now − glucoseDate` | ❌ **NO — stays green while every enact fails** |
| **Dot** (`loopDotColor`, :719) | **loop recency** — `now − lastLoopCompleted`, 6/20 min | ✅ yes — amber then red |
| **Status text** (:713) | `"CLOSED · 27m"` | ✅ yes |
| **BG number + arrow** (:646) | dims, drops the arrow, adds an age line when stale | ✅ yes |
| **Eventual BG** | last COMPLETED cycle — frozen while enacts fail | ❌ silently stale (#14) |
| **IOB / COB** | live from the stores, no pod needed | ⚠️ keeps moving, widening the gap |
| **Transient bolus label** | set on request, cleared on pod ack | ⚠️ correct state, stale PAINT (#15) |

## The two real defects

### A. The ring is the biggest element and it tracks the wrong thing
`loopFreshness` was defined as BG recency (2026-07-24) and is "meaningful whether the loop is open or
closed" — reasonable in isolation. But it is the dominant visual, and a user reads it as *"is the
system working?"* During e141 (2026-08-19, 27 min with `enact=FAILED communication(nil)` every cycle)
the ring was green throughout, because G7 readings kept arriving.

**The truth WAS on screen** — red dot, `CLOSED · 27m` — just not in the element the eye goes to.

**Candidate:** the ring should reflect the WORSE of BG recency and loop recency. Glucose fresh but no
completed cycle in 20 minutes is not a healthy system, and the ring should stop saying it is. Keep the
dot and text as the detail; make the headline honest.

### B. Live values and cycle-bound values drift apart, unlabelled
IOB/COB render off the stores every tick; eventual BG and the recommendation only update when a cycle
COMPLETES. When enacts fail, the live half keeps moving and the predicted half freezes — measured at
e141: `dosemath IOB 1.10` vs `glance IOB 1.20`, `lastCompletedAge=1622s`.

**Candidate:** mark the prediction stale using `lastCompletedAge` (already computed, already logged),
with the same treatment glucose already gets — dim it and show the age. See #14.

## The paint problem underneath both (#4, #15)

The glance ticks on the loan controller's serial queue — **the queue the pod link holds**. So during a
bolus or a reclaim ladder the screen cannot repaint, and shows whatever it last painted. Observed
2026-08-20: a bolus delivered (haptic + audible) while the screen still read `starting 0.85 U…`;
swiping away and back cleared it, because that forces a repaint.

**This makes every other freshness fix unreliable**, since a correct state that cannot be painted is
indistinguishable from a wrong one.

**Candidates:** (1) push a repaint at state transitions — pod ack, cycle end, enact failure — rather
than waiting for a tick that is blocked behind the radio; (2) let the glance read a snapshot instead of
taking the queue.

## Recommended order

1. **Push-repaint on bolus ack** — smallest, fixes the observed misleading label, and unblocks the rest
2. **Ring reflects the worse of BG and loop recency** — the headline stops lying
3. **Mark the prediction stale via `lastCompletedAge`** — the drift becomes visible
4. **Glance off the serial queue** — the structural fix; larger, do last

## How to verify
Put the POD in a faraday cage during a loan: glucose keeps flowing, enacts fail. Correct behaviour is
ring degrading, prediction marked stale, IOB/COB either frozen or labelled — and every one of those
repainting WITHOUT a swipe.
