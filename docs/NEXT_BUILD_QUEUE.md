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

---

## After the 2026-08-20 10:47 ship (ladder self-diagnosis + ring rule)

**Shipped:** census `anySeen`/`skipped`, watchdog 5 s/15 s capped at 3 per arm, sticky
`lastKnownLoanPodId`, dwell-qualified adopt gate, `noteLinkTornDown` for the two
unattributed cancel sites, `freshConnect` obeying its verdict, ring on loop age alone.

**Dropped from the plan, deliberately:** the reclaim ladder re-issuing a dead connect.
The 13:00:16 trace shows the peripheral `.disconnected` for all 14 reads, so no connect
was ever issued — there is nothing to re-issue. See `POD_ENACT_DIAGNOSIS.md`.

### 1. `testANewGrantDoesNotInheritAFailedTakeoversClock` is RACY

Failed the gate at 10:30 (`got: +0s`, expected `+10s`), then passed **3/3 in isolation**
and the full gate passed on re-run. Nothing since the last green gate (08-19 22:56)
touches `PodLoanPhoneController.swift` or its test.

Mechanism: `armT1(for:)` — which stamps `grantOfferedAt` — runs at the END of a deep
async chain (carb fetch, glucose fetch, prediction snapshot) inside `offerGrant`. The
test advances its fake clock and injects the status report immediately after
`offerGrant` returns. Under full-suite load the stamp has not landed, `grantOfferedAt`
is nil, and `elapsed` falls through to `?? 0`.

**This is not only a test bug.** The same window exists in the field: a status report
arriving before `armT1` lands makes the phone report `+0s`, and `elapsed < ceiling` is
then trivially true — the takeover-progress ceiling that exists to stop a wedged watch
holding the pod hostage would not fire. The window is small (the watch has to answer a
grant faster than the phone finishes its own snapshot) but it is the wrong direction to
fail in. Fix: stamp `grantOfferedAt` when the grant is DECIDED, not when the message
finishes being built.

### 2. Deferred, with reasons (asked 2026-08-20)

- **stuck-`.connecting` handling** — the detector shipped (dwell-qualified adopt gate).
  Build the handling only if a ladder actually prints `WEDGED`. This morning's failure
  was `.disconnected`, so it is not that bug.
- **grant-gate evidence-keyed replacement** — unrelated to pod enact; own build.
- **glance off the queue** — UI responsiveness; own build.
- **G7 watchdog: D2W stamping, per-arm baseline, teardown cancel** — G7 held 34/34
  overnight. Real, but it protects a path that is currently working.
- **Unit tests for the radio layer** — still zero.
