# Prediction & Dosing — the concepts, and how each implementation realises them

**Status: DRAFT, awaiting Jeremy's agreement. Not yet authoritative.**

**Why this document exists (2026-08-18).** Prediction questions on this project get re-derived
from scratch every few weeks, and the same handful of mistakes recur. The mistakes are almost
never arithmetic — they are *seam* errors: which curve, which book, which instant, which
schedule. This document fixes the concepts once, then translates them into each implementation,
so a claim can be checked against the right layer instead of the nearest plausible one.

It supersedes, for the next-dev line, pure's `docs/PREDICTION_DOSING_SURFACES.md`. That document
remains correct **for pure** and is still the better read for the hand-rolled loop. Part 4 lists
exactly what changed, because one of its central tables is now wrong on next-dev and copying it
across would have encoded a false fact with a project document's authority.

---

# Part 1 — The concepts

These are implementation-independent. If an implementation contradicts one of these, that is a
finding, not a variation.

## 1.1 The question every dosing debate collides with

> When a temp basal is running, how much of its *future* delivery does each surface assume?

Different surfaces answer differently, deliberately. Conversations that do not name the surface
first go in circles. Name the surface, then answer.

## 1.2 The surfaces and their conventions

**(a) The automatic loop — prediction and temp-basal dosing: the running temp is trimmed AT NOW.
Zero forward credit.**

The reason is not conservatism, it is double-counting. The recommendation this cycle produces
*replaces* the running temp. Crediting the temp's remaining span would count the very delivery
being re-decided. Each cycle re-derives the temp from delivered-insulin-only, and the next cycle
books whatever was actually delivered in between.

The practical difference between "trimmed at now" and "trimmed at the next cycle" is one cycle's
delivery — at 4 U/hr, ≤ ~0.3 U — and it self-corrects on the following cycle.

**(b) The manual-bolus and carb-entry screens: the running temp RUNS TO ITS SCHEDULED END, and
the recommendation is only the insulin needed on top of it.**

Different question, so a different convention. A manual bolus does not replace the loop's temp;
it is added alongside it. The loop has already arranged that basal delivery, so the forecast the
person is deciding against must include it, and the recommendation must not re-ask for insulin
the pump is already going to give.

**(c) Displayed IOB: see Part 4 — this is the convention that changed between implementations,
and it is the one most often asserted wrongly.**

## 1.3 Invariants

These hold on every implementation. A violation is a bug.

1. **No forward credit for temps anywhere in dosing.** Only delivered insulin sizes a dose.

2. **One question, one book.** A number shown to a person and the number used to dose must derive
   from the same source. Staleness is tolerable; *divergent sources* are not. A displayed figure
   that is one cycle old but from the dosing book is honest. A displayed figure that is
   instantaneous but from a different book is a lie that looks like precision — it vouches for a
   hidden number it has never seen. This is the 2026-08-18 defect: the glance read the ledger and
   showed IOB 1.85 U while the algorithm read an unwritten store and dosed on 0.00 U, same
   screen, same second, nothing logged.

3. **Refresh cadence is a lesser concern than source.** Refresh-on-insulin-write,
   refresh-per-cycle and refresh-on-delivery are near-equivalent; the only thing lost is decay
   between cycles, which at 5-minute granularity is noise. Do not trade invariant 2 to buy
   cadence.

4. **A displayed prediction may be stale, but must be MARKED, never blanked.** A blanked forecast
   reads as "no prediction", which is its own lie. Grade freshness instead.

5. **Insulin delivery Uncertainty resolves toward assuming insulin has been delivered, rather than that it hasn't.  In other words, the IOB used for dosing needs to be the upper bound of what it could be given delivery uncertainty.

6.  Carb recording uncertainty resolves towards not recording.  Under closed loop, the existence of carbs results in delivery of insulin.  If the carbs are fake, or doubled, or overstated, this creates risk.  

## 1.4 What the algorithm is, conceptually

One function of many inputs: glucose history, doses, carb entries, and the basal / sensitivity /
carb-ratio / target timelines in, prediction and recommendation out.

**"Stateless" needs to be said precisely, because conflating three senses of it is how this
document got it wrong the first time.** Jeremy challenged the original wording and was right.

1. **Algorithmic state** — does cycle N's output depend on cycle N−1's *output*? **No, in either
   implementation.** Both recompute from the stores every cycle. This is the sense most people
   mean, and by it pure was already stateless.

2. **Implementation caches** — are intermediate effects held between calls and invalidated by
   hand? **Pure: yes. next-dev: no.** This is the only sense in which the rewrite changed
   anything, and the difference is a bug class rather than a behaviour: a *missed* invalidation
   serves a stale effect into a live dose, and a function with nowhere to keep one cannot.

3. **Reading stored history** — every run reads past glucose, doses, carbs and discrepancies.
   That is input, not memory, and it is true of both.

**Retrospective correction is the case worth settling, since it is the obvious candidate for real
cross-cycle state — and it is not one.** `IntegralRetrospectiveCorrection.computeEffect` resets
`recentDiscrepancyValues = []` at the top of every call
(`LoopAlgorithm/Sources/LoopAlgorithm/RetrospectiveCorrection/IntegralRetrospectiveCorrection.swift:121`)
and rebuilds the array from `retrospectiveGlucoseDiscrepanciesSummed`, which arrives as an input.
Its mutable properties are scratch space *within* a call, not memory *between* calls, so the
integral is recomputed from stored discrepancies each cycle rather than accumulated across them.

That is a fix, not an accident: the original integral RC did accumulate, which was raised against
it at the time, and the non-accumulating form is what shipped in the extracted package
(`2ccdaab`, Feb 2024). The accumulating version predates this repository, so the exchange itself
is not visible in this history — the code is, and it is decisive.

**So what the rewrite actually bought:** not the removal of an algorithmic dependence, which was
never there, but the removal of an entire family of stale-forecast bugs whose signature is a
correct algorithm fed a cached input nobody remembered to invalidate. Worth keeping in view
because the 2026-08-18 watch defect was the same shape one layer out — not a stale cache, but a
correct algorithm reading the wrong book.

Consequences worth stating, because they are repeatedly forgotten:

- **Recomputing is normal and cheap.** Never special-case an input to avoid a recompute
  (back-dated carbs, deletions, edits). Recompute is the design.
- **Every dosing error is time-bounded.** Insulin is exactly 6 h; carbs tail to 7.5 h. Check the
  decay horizon before building recovery machinery. Latched flags, however, never decay.
- **The overrides scale the timelines, not just the target.** Basal, ISF and carb ratio all move
  with an override. Moving the target alone would make every neutral temp a high temp in override
  terms.

---

# Part 2 — next-dev on the phone: the reference implementation

This is the layer to check a claim against before asserting anything about the watch.

## 2.1 Three algorithm runs, not one shared snapshot

A natural assumption — and wrong. The phone runs `LoopAlgorithm.run` **three separate times**:

| Purpose | Site | Recommendation type |
|---|---|---|
| Display | `LoopDataManager.swift:576` → `:618` | `.manualBolus` |
| Dosing | `LoopDataManager.swift:744` | `.tempBasal` / `.automaticBolus` |
| Manual bolus screen | `LoopDataManager.swift:863` | `.manualBolus` |

The dosing output is a local `var` never assigned to `displayState`, and `loop()` never reads
`displayState`.

## 2.2 So what actually prevents divergence

Not a shared snapshot. **One store, and every displayed scalar is a field of an algorithm output
rather than an independent query.**

- IOB on screen is `output.activeInsulin` — the same value that caps the dose
  (`LoopAlgorithm.swift:790`, `:799`, returned `:814`; read for display at
  `LoopDataManager.swift:22-27` → `:138-140` → `StatusTableViewController.swift:573`).
- There is no IOB computation anywhere in the phone's Views or View Controllers.

Display and dosing can therefore differ **in time** by at most one refresh. They cannot differ
**in source**. That is invariant 2 realised structurally, and it is the property the watch must
copy — not the snapshot mechanism, which does not exist.

**Permitted exception, and its exact shape:** the status screen re-queries stores directly for
the two *history pictures* behind the chart (`StatusTableViewController.swift:515-528`), never
for a printed scalar. The IOB number directly above those dose bars still comes from the
snapshot. An independent re-query is allowed for a drawing nobody doses on; never for a number.

## 2.3 One input-assembly function, with named knobs

`fetchData` (`LoopDataManager.swift:352-357`) is the only dose reader for the algorithm, with a
single store call at `:374-377`. Legitimate display/dosing differences ride as **parameters**,
never as a second data path:

| Knob | Display | Dosing | Manual bolus |
|---|---|---|---|
| `projectOngoingDoses` | `true` (`end: nil`) | default | default |
| `ensureDosingCoverageStart` | `now − 24 h` | — | — |
| `presumePresetEndingNow` | — | — | set when truncating an override |
| post-hoc trim | none | `input.doses.trimmed(to: loopBaseTime)` (`:719`) | none |

The trim on the dosing path **is** concept 1.2(a). The absence of it on the manual-bolus path
**is** concept 1.2(b). Same idea as pure's `basalDosingEnd`, different mechanism — see Part 3.

`projectOngoingDoses` exists so the display forecast does not assume scheduled basal silently
resumed at a suspend instant, which would be optimistic by exactly the missing-basal effect
(upstream `d971f9d2`, Pete Schwamb, 2026-06-02). Note the scope: it concerns an ongoing
**suspend**, not forward credit for a temp.

## 2.4 Refuse rather than reinterpret

Where dosing must not consume what display may, the dosing path throws:

```swift
guard !input.recommendationType.automated || basalEnd <= input.predictionStart
else { throw AlgorithmError.futureBasalNotAllowed }   // LoopAlgorithm.swift:700-703
```

`.tempBasal` and `.automaticBolus` report `automated == true`; `.manualBolus` does not. This is
why an untrimmed live temp is a hard error on the automatic path and merely a different
convention on the bolus screen.

## 2.5 Refresh

`loop()` ends with `await updateDisplayState(...)` (`LoopDataManager.swift:834`), placed after
the do/catch so it runs on both the success and the error path. *(Fork addition, `13fe656f` —
not stock.)*

---

# Part 3 — Translation between implementations

| Concept | pure (hand-rolled) | next-dev (LoopAlgorithm) |
|---|---|---|
| Trim a continuing dose | `getGlucoseEffects(…, basalDosingEnd:)` | `input.doses.trimmed(to:)` |
| Dosing convention 1.2(a) | `basalDosingEnd: now()` | `trimmed(to: loopBaseTime)` in `loop()` only |
| Bolus convention 1.2(b) | `basalDosingEnd: nil` (pending-inclusive timeline) | no trim on the manual-bolus path |
| Two cached effect timelines | `insulinEffect` / `insulinEffectIncludingPendingInsulin` | **gone** — one input, two call sites |
| Display IOB | `DoseStore.insulinOnBoard(at:)`, untrimmed | `output.activeInsulin` |
| Effect caches | hand-invalidated | none; the algorithm is stateless |

**Trimming is not one operation.** `DoseEntry.trimmed(to:)` pro-rates a `.units` dose (a bolus)
by the fraction of its duration retained, and merely shrinks the window of a `.unitsPerHour` dose
(a temp), preserving its rate. So a blanket trim is correct for temps and destructive for
boluses. Get this wrong in either direction and it is a dosing bug:

- trim a temp too little → forward credit, and on the automated path a hard
  `futureBasalNotAllowed` refusal;
- trim a bolus at all, when it was booked with a forward-looking delivery window → its volume
  pro-rates toward zero and the insulin vanishes from the book.

---

# Part 4 — What genuinely changed, and what that invalidates

**The displayed-IOB convention changed. This is the one to un-learn.**

pure (and LoopKit's `InsulinMath`) bounded the IOB integral at
`floor((time + model.delay) / delta) * delta`, walking ~10 minutes *past now*. Because
`percentEffectRemaining` is 1.0 for t ≤ delay, those future segments scored full weight — so
displayed IOB counted roughly the next 10 minutes of scheduled-but-undelivered insulin.
pure's document records the exact replication: a 3.1 U/hr net temp evaluated 10 minutes in
contributed **1.292 U untrimmed vs 0.517 U trimmed** — 0.775 U of not-yet-delivered insulin in
the displayed number.

**On next-dev that is fixed upstream.** `aeffea8` "Fix delta-scale IOB ripple for basal segments
longer than delta (#35)" (Pete Schwamb, LoopKit/LoopAlgorithm, 2026-07-14) replaced the bound
with `let upper = min(time, doseDuration)` and a midpoint Riemann sum with a weighted partial
final chunk. IOB now integrates **only up to now**. His commit is explicit that it is *"scoped to
the insulinOnBoard path; glucoseEffect (and therefore dosing) is unchanged."*

Consequences:

- **Do not cite pure's 1.292/0.517 table for next-dev.** It describes a bound that no longer
  exists.
- The "hand-computing IOB × ISF is systematically misleading whenever a temp is running" warning
  is substantially weaker on next-dev. The residual forward biases are the `max`-of-adjacent-grid
  sample and the untrimmed dose *window* — not the delay walk.
- Concept 1.2(c) on next-dev is therefore: **displayed IOB is delivered-so-far, weighted by
  remaining effect.** Which is the intuitive answer, and was not previously true.

---

# Part 5 — The watch (Sport Mode, next-dev port)

## 5.1 The one platform constraint that is real

The watch's `DoseStore` is **never written**: `pumpManager(_:hasNewPumpEvents:)` discards every
row deliberately, and no other writer exists in the extension. `SessionInsulinLedger`, fed at
enact time, is the only insulin book. That constraint is genuine and cited.

**It is also the excuse that concealed the 2026-08-18 defect.** "The watch is different" was true
about needing a ledger and false about reading the store for dosing, and the true half made the
false half invisible for weeks. Demand a specific, cited constraint before accepting any
watch-specific departure.

## 5.2 Where the watch stands against Part 1

- Invariant 1: holds — temps are trimmed to `baseTime` in `fetchAlgorithmInput`, boluses are not
  (see Part 3 for why the asymmetry is required).
- Invariant 2: **partially violated, work in progress.** The glance evaluates
  `ledger.insulinOnBoard(at: now())` live while the algorithm's `activeInsulin` is cycle-time —
  one book now, but still two derivations over two clocks and two schedule resolutions.
- Invariant 3: the watch is more coherent than the stock phone here, deliberately: a store
  mutation re-runs the full cycle including enact, so eventual and temp are products of one pass.

## 5.3 Known open divergences

Tracked separately in the parity register. Summary of the live ones at time of writing:

- glance IOB vs stock chart-page IOB (live vs cached, one swipe apart);
- `recommendManualBolus` writes the display caches, so unsaved carbs reach the glance and the
  per-cycle `.manualBolus` run clobbers the `.tempBasal` run's curve;
- the `?? activeInsulin` display fallback, which does the thing R35 bans on the dosing side;
- override netting: the glance nets historical temps against the currently-resolved override,
  the algorithm against what was in force at each temp's start.

---

## How to use this document

Before asserting anything about prediction or dosing:

1. **Name the surface** (1.2). Most disagreements dissolve here.
2. **Check Part 2** — the phone is the reference; if the watch differs, that needs a cited reason.
3. **Check Part 4** before quoting anything from pure's document.
4. **Cite file:line, read the code, not the comment.** Several comments in this tree are stale and
   one was actively self-contradictory — "it is the ONLY insulin book — dosing and display still
   read the DoseStore" — which is precisely where the exemplar defect hid.
