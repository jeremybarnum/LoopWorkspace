# Next-build queue — written at session close 2026-08-20 ~10:15

## Jeremy's ring rule (DECIDED — deviation from stock, deliberate)
Ring = a function of SUCCESSFULLY ENACTED loop, applied generously: if the pod's availability is
unknown but not yet needed, that is GREEN. Never grey/degrade merely because we connect to the pod
less actively between doses. Concretely: BG freshness drives the ring normally; degrade only when
loop-completion age passes the genuine-failure threshold (~16-20 min, the e141 class); nil
lastLoopCompleted at loan start falls back to BG freshness — no grey takeover starts. The current
worst-of implementation (de3cb5a9 + 28cd6c0) is STRICTER than this and must be relaxed to match.

## From the cold review (agent, 2026-08-20) — UNFIXED, in priority order
1. **freshConnect ignores the interlock verdict** (BluetoothManager ~:1265): `_ = noteConnectIssued(force:true)`
   then connects unconditionally. The iOS interlock logs "REFUSED" and counts it — and the connect goes
   out anyway. e141's "refused four freshConnect attempts" was false as to effect. Fix must preserve
   the never-refuse-a-recovery invariant.
2. **G7 watchdog blinded when phone present**: lastDeliveryAt stamps on IGNORED D2W connection events,
   so a wedged pending connect never ages past the threshold. Also: per-arm baseline reset never
   ported from the pod twin; timer never cancelled on teardown (fires forever on a dead manager).
3. **Pod watchdog silenced in the stuck-.connecting wedge** (the podBusy guard) — consider cancelling
   a .connecting peripheral older than a bound instead of skipping; cap/backoff the 20s restart churn.
4. **Adopt-gate instrument false-positives** during every healthy in-flight adopt (pod advertises
   while .connecting) — qualify by dwell time or it manufactures the next false lead.
5. **Cancel-attribution holes**: enterBackground cancel (~:1349) unattributed AND a candidate
   mechanism for the stranded-pendingAdopt screenshot (wrist-down cancels an in-flight adopt, no
   delegate callback); "cancelled:didConnect-dupe" is dead code (intent already closed as resolved).
6. **Census fallback**: corrected census still falls back to autoConnectIDs membership when the
   marker is nil — between-ladders adverts remain uncounted.
7. **Grant-gate replacement unbuilt**: the evidence-keyed version (live-path arrival + refusal in the
   sendMessage REPLY) exists only as a comment in PodLoanPhoneController.
8. **Tests: zero.** Two watchdog generations shipped, first one had a 69-firing bug a unit test would
   catch. WatchAppTests seams exist. See also the parked guardrail-tests idea in RADIO_LAB.md.
9. Before running the trigger-(c)-off falsification: add a lab gate for the G7 watchdog, or its
   320s recycle confounds the reproduction. And grep the overnight log for scan-watchdog lines to
   confirm the 34/34 attributes to the scan-arm alone. Battery cost of continuous scanning: watch
   died at 10%->dead in ~3h that night — measure before calling the fix free.

## State
- TestFlight has build 28cd6c0 (shipped in error — upload completed before the abort). Do not install;
  the next deliberate build supersedes it.
- 28cd6c0 already contains: watchdog scan-lifecycle fix, predictionStale rendering, main-hop on the
  bolus repaint, e141-circularity docs correction, cancel attribution, census-by-address, adopt-gate,
  ring worst-of (to be relaxed per the rule above), bolus-ack repaint, Radio Lab.
