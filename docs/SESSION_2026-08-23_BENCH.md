# Bench session 2026-08-23 — the day the pod layer got boring

One day, one bench (real G7, water pod, phone + watch), part of it on an airplane with a
backwards-stepping clock — which turned out to be a feature. Everything below is measured,
not estimated; log excerpts live in the session transcripts and the numbers are quoted
exactly. Builds: 1085 (morning) → TestFlight 132 / `ea5e231` (evening) → `4f9b00c` (shipped
end of session).

## Headline numbers

| path | start of day | end of day | mechanism |
|---|---|---|---|
| reclaim (per enact) | ~30.5 s median | **4.0–4.5 s** | 6 s read watchdog + stale-manager switch (1085), then skip the deaf 4 s discovery scan and dial cold (~2.2 s connect, measured 11/11) |
| hand-back, watch side | ~20 s spin | **< 2 s** | finalize no longer dials for a freshen the phone discards; offer leaves in the same millisecond |
| hand-back, phone verified | ~27 s | **5–6 s** | the reclaim DIALS at re-arm (it never dialed at all — see below) + skip-discovery for just-released pods |
| forced reclaim | ~27 s, no UI | **1–5 s, live tile + bar** | same dial fix + tile gate widened to ladder phases |
| cold pod (5 min idle) | unmeasured (2 attempts died) | **9.3–12.3 s → then same ~4 s after the scan fix** | idle time proven irrelevant — the cost was always ours |

## Root causes found today (each verified in code AND on hardware)

1. **The phone reclaim never dialed.** `reclaimConnection()` → `rearmConnection()` →
   `connectToDevice()` only dials an *unknown* peripheral (ours is always known);
   `autoReconnect()` returns immediately under connect-on-demand; the settle's verification
   read was gated on `isConnectionReady()`. Nothing dialed — the 20 s escalation's scan-adopt
   was what connected, every time. Every 24–28 s settle was this. Fix: dial at re-arm
   (`skipDiscovery` — the pod was released seconds ago and is guaranteed advertising).
2. **The watch's fresh-discovery scan is deaf.** 4 s of listen-first heard **zero adverts in
   8/8 reclaim ladders** (pod at −50 dBm) while every cold connect landed in ~2.2 s. The scan
   is phone physics (10–16 s duty-cycled cold connects there); on the watch it was pure loss —
   and 4.1 s scan + 2.2 s connect = 6.3 s, just past the 6 s read watchdog, which manufactured
   the rigid read-1-fails/read-2-succeeds ~10 s pattern. watchOS now dials cold immediately.
3. **The hand-back freshen dialed for a discarded answer.** "When the link is down this fails
   instantly" was standing-connection-era truth; under connect-on-demand the read dialed,
   sent nothing while finalizing, the pod hung up (#7 at ~7 s), and the read burned its full
   20 s timeout — for an odometer the phone re-reads authoritatively anyway. Freshen now runs
   only over an already-up link.
4. **The elapsed counter was the only progress display, and the two-stage machinery behind it
   was calibrated to a distribution (4–190 s) that no longer exists.** Replaced with one
   10 s promise, a real bar via the tile's native `pumpLifecycleProgress`, and no counter.
5. **Two watch-UI staleness bugs, distinct mechanisms:** (a) the phone tile's
   `.PumpManagerChanged` observer never set `.status` in the refresh context, so ownership
   flips could render late; (b) the glance's pushed-transition path (`refreshNow`) paints the
   previous mirror by construction and had nobody to paint the rebuilt one when the render
   loop was down — a phone-forced reclaim with the wrist down stood stale for 111 s until a
   tap. Both fixed; (b) via a one-shot mirror observer so every poke finishes its own paint.

## The wedges — now two named diseases with two cures

**Never cross-contaminate the remedies** (full table: §4.67 of POD_CONNECTION_MODEL, mirrored
from the pure line's WCSESSION_7006_BRIEF):

- **BLE orphan wedge** (`#11`s, ladder-never-connects, adverts go quiet): watch BT toggle,
  field-proven — and now automated: the **launch reap** cancels a dead predecessor's pending
  pod connects at first poweredOn (pod identifiers ONLY; the G7's standing pending connect is
  the piggyback acquisition mechanism and is never touched). Force-quit is now a reset, not a
  poison. Cure premise (successor process can cancel bluetoothd's app-keyed request) still
  needs one on-wrist validation: force-quit mid-takeover → relaunch → `[launch-reap] …
  CANCELLED`.
- **WC transport wedge** (grants vanish one-way; `isWatchAppInstalled=false` with the app
  present; #113/#108 fire): captured **in stereo four times** tonight. Watch→phone stayed
  alive (requests crossed, grants issued); phone→watch was dead. Failed cures, all proven
  tonight: watch BT toggles, force-quits (both apps), watch reboot, **phone reboot**, ground
  network. **The cure: reinstalling the WATCH app** — `appInstalled` flipped healthy at
  19:42:18, 39 s before the new watch app's first launch, matching the pure line's 8/17
  case (cleared only by a TestFlight install). The state is persisted watch-app registration,
  not daemon runtime. Candidate trigger, first ever logged: the phone's clock stepping
  BACKWARDS (in-flight re-sync; a 2-minute step observed mid-log). Bench-reproducible:
  airplane mode + manual clock change. Untested.

Every safety mechanism held through all four wedge occurrences: dead-man T1 abandoned the
undeliverable loans, force-reclaims recovered in 1–5 s, R37 audits CLEAN, R33 cancelled the
boundary temps, ledgers exact (residuals ≤ 0.05 U all day, most 0.000).

## Also today

- **The R37 materiality band works as designed and will fool bench tests:** sub-0.20 U
  odometer residuals are absorbed silently (dosing stays closed). Bench boluses are 0.05–0.25 U,
  so the "book manual insulin + open loop" path needs a ≥0.5 U test bolus to demonstrate.
- **Ring/loop recency now inherits across the loan boundary** (optional protocol fields, both
  directions, tolerant decode). First field sighting was honest: it carried a 68-minute-stale
  phone loop and the wrist said so.
- **The appInstalled glitch detector** shipped, fired twice, and taught us its own lesson:
  the first firing was eaten by a flight Focus mode → the notice is now `.timeSensitive`.
- **Launch forensics caught the watch-app death ritual** for the first time: five launches in
  31 s, `sincePrevLaunch=3–23 s`, footprint 6–17 MB at launch — small, so not a memory kill
  at launch. Still open, but no longer invisible.
- The revoke path builds its final offer AFTER tearing down the pump, so revoke hand-backs
  carry no odometer and skip the AUTHORITATIVE reconcile line (e181). Pre-existing, bounded
  (the phone reads the pod itself), queued.
- `cb:` clock, `g7pending=`, `[domain#code]` tags, `[glance-stale]`, `[launch-reap]`: all new
  instruments fired in the field today; `[glance-stale]` reading zero is what killed the
  queue-contention theory and redirected the glance fix to the real mechanism.

## Open items, ranked

1. Validate the launch reap's cancel-reaches-bluetoothd premise (one force-quit experiment).
2. WC wedge trigger repro: backwards clock step on the bench; and the #113/#104 message text
   should say "update/reinstall the watch app" once one more field confirmation lands.
3. Watch-app death ritual: forensics now armed; need one occurrence with the new data.
4. Revoke-path odometer (above).
5. Tier-2 lean pass after a field week: shrink the 14-read ladders, prune takeover scan
   machinery, drop the settled Radio Lab toggles' storage.
6. The ~4 s watch-tap-to-phone-ack on hand-back start: composition known (drain + tick),
   accepted as a nit.
