# Review pack — claims from the last hour, graded

For independent review. Written by the same author who made the claims, so treat the grading itself
as suspect and check the citations.

## Track record this session (context for how much to trust the below)

Fourteen hypotheses registered over ~36 hours; most died. Specifically WRONG and later retracted:
G7 scan contention (twice), connection-slot exhaustion, leaked-intent leak, duplicate-connect as the
cause of ladder failure, phone contention (H5 — was the *headline* finding for a day), background-scan
throttling (H6 — built on a measurement error I made), install-order determining `appInstalled`,
two-centrals starvation (H10), held-link deafness (H11/H12), `EAGER_LINKING` fixing the build phantom
(claimed twice, wrong twice), and the debug-dylib crash-loop diagnosis. **Also shipped two bugs of my
own** (an interlock that blocked the watch's own connects; a watchdog that fired 69 times on a healthy
night). The pattern in the failures: arguing from mechanism rather than measurement, and over-reading
single observations.

---

## CLAIM 1 — The G7 scan-arm fix works. **Confidence: HIGH**

**Change:** `G7BluetoothManager` armed its scan only when `activePeripheral == nil`; the known-sensor
branch issues a bare `connect()` and makes that non-nil, so after any ride there was NO scan. Changed
to `activePeripheral?.state != .connected`.

**Evidence — two independent runs, plus a third-party observer:**
- Overnight: **34 consecutive `INGEST src=direct-G7`**, 02:21→05:06, phone Bluetooth OFF, ages 3–7 s.
  Stopped only when the watch battery died.
- This morning: **24 ingests**, unbroken 5-min cadence through another phone-absent window.
- Mac observer (passive, never connects) shows the sensor holding 293–298 s collected cadence
  throughout, escalating to ~60 s distress ONLY after the watch died.
- Pre-fix, same scenario: seven consecutive missed windows, 20–40 min outages.

**What is inferred, not measured:** the explanation that *our* scan was also carrying D2W's pending
connects (hence both apps recovering together). Consistent with the shared-receiver model and with
observation, but not directly instrumented. **The fix's efficacy does not depend on that story.**

**How to falsify:** Radio Lab → trigger (c) off should reproduce the 20–40 min outages on demand.
NOT YET RUN. This is the strongest available check and it is cheap.

---

## CLAIM 2 — `adverts=0` was partly MY instrument lying. **Confidence: HIGH (code), UNVERIFIED (field)**

The census I added counts only when `isOwnPod = autoConnectIDs.contains(peripheral.identifier)`.
`releaseConnection()` → `disconnectFromDevice()` → `autoConnectIDs.remove(...)`. So after every
post-dose release the pod's adverts stop being counted even if received.

**Status:** read from source, not yet demonstrated in the field. If true, two nights of "the watch
cannot hear the pod" were partly artifact. Corrected build counts by address match off the parsed
advertisement (as the adopt path itself does). **Not yet run.**

**Caveat against my own claim:** it cannot explain ladders where `adverts>0` AND the pod was heard —
those are real. And the Mac independently confirmed the pod advertising during failures, which does
NOT depend on my census. So the deafness observations are not *entirely* artifact.

---

## CLAIM 3 — "We cancel our own connect." **Confidence: LOW-MEDIUM. n=1.**

**The single observation (L10, 09:11:37, this morning):**
```
[connectOnDemand] pod heard -> connecting on fresh advert
[intent] connect via timedConnect            → open=1 issued=13
[intent] connect via adopt-retry SUPPRESSED (connect in flight)
[intent] cancelled                            → open=0 cancelled=6
Pod disconnected 0B2EDBAA-… nil
```
Ladder then failed after 14 reads with `adverts=6 last=6s rssi=-81`.

**What this does and does not show.** It shows a connect issued and then closed as "cancelled" rather
than resolved/refused, in a ladder that heard the pod. It does NOT show which of nine call sites
cancelled — the ledger doesn't record that (now instrumented, unrun). It does NOT establish this is
the general cause: L7, L11–L14 failed with `adverts=0`, a different signature.

**I stated this as "found it." That was over-confident on one log excerpt.** At most: a real anomaly
worth naming, one plausible mechanism among others, and the instrumentation to settle it is built but
untested.

---

## CLAIM 4 — The ring tracks BG recency, not loop health. **Confidence: HIGH (code-verified)**

`GlanceView:645` computed `loopFreshness` from `now − glucoseDate` with home-grown 7/15-min
thresholds. The dot (`:719`) separately used `lastLoopCompleted` with stock's 6/20. So during e141's
27 minutes of `enact=FAILED` the ring stayed green while the dot was red.

**Fix:** adopt LoopKit's shared `LoopCompletionFreshness` (fresh ≤6m, aging ≤16m — the phone's own
type), ring = worst-of BG and loop recency. **Not field-tested; visual change only.**

---

## CLAIM 5 — Screenshot analysis (`scanning=false`, stranded `pendingAdopt`). **Confidence: LOW. Single frame.**

`scanning=false, marker=nil, pendingAdopt=<pod>, open=0, cancelled=9, ORPHANED=1, anyDiscover=23`.

I read this as a wedge. **But it is one frame, plausibly taken between ladders**, where marker=nil and
no scan is expected. `anyDiscover=23` is a session total, not a live rate — I initially cited it as
evidence the radio was healthy *at that moment*, which it is not. The genuinely odd part is
`pendingAdopt` set with `open=0` (an adoption whose connect produced neither terminal callback). I
verified in source that a stale `pendingAdopt` does not block re-adoption, so it is a symptom.

---

## Built but NOT shipped and NOT run (all instrumentation, no behaviour change)
- cancel attribution (`cancels=freshConnect:3,…`) — names the culprit for CLAIM 3
- corrected advert census by address — tests CLAIM 2
- `heardNotAdopted=N` + `[adopt-gate]` line — names the gate when the pod is heard but declined
- ring/prediction freshness (CLAIM 4)
- watchdog false-positive fixes (already shipped 9ed250d)

## Known gaps in my own reasoning, unresolved
1. **Two distinct ladder failure signatures** (`adverts>0` vs `adverts=0`) are being discussed as one
   phenomenon. They may be different bugs.
2. **The scan watchdog only polices while the loan marker is armed**, so it slept through this
   morning's failures (`scanWD=0` proves nothing). Scope fix identified, not written.
3. **Why `scanning=false` between ladders** is unexplained; may be correct behaviour.
