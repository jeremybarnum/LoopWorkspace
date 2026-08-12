#!/bin/zsh
#
# testflight.sh — headless archive -> upload for the from-stock Sport Mode build.
#
# Replaces the babysat Xcode flow (Product > Archive, Organizer > Distribute).
# After this succeeds, App Store Connect processes the build (~5-15 min) and
# TestFlight notifies the phone; installing from TestFlight stays manual.
#
#   Usage:  Scripts/testflight.sh                 # archive + upload
#           Scripts/testflight.sh --archive-only  # stop before the upload
#
# Build numbers: CURRENT_PROJECT_VERSION in VersionOverride.xcconfig is a base;
# the export options enable manageAppVersionAndBuildNumber, so App Store Connect
# assigns the next available number at upload (same behavior as the Organizer).
# Do not bump the source value.
#
# Auth: App Store Connect API key (CI-grade; independent of the Xcode account
# session, which proved fragile — "Failed to Use Accounts" after a re-sign-in).
# The key must be ADMIN role: cloud-managed distribution signing (which the
# app's store profiles use) is gated to Admin API keys (Apple forums 698117).
# Key file: ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
# Signing stays cloud/automatic via -allowProvisioningUpdates.
# Outputs live OUTSIDE the repo in ../TestFlight-fromstock (archives pruned to 3).

set -euo pipefail

ASC_KEY_ID="2NXQW3ZWCX"
ASC_ISSUER_ID="69a6de91-92af-47e3-e053-5b8c7c11a4d1"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
[[ -f "$ASC_KEY_PATH" ]] || { echo "ASC API key missing: $ASC_KEY_PATH"; exit 64; }

ROOT="${0:A:h:h}"                      # superproject root (this file is in Scripts/)
BASE="${ROOT:h}"                       # the March2026 directory
DD="$BASE/.dd-fromstock-archive"       # isolated Release DerivedData (CLAUDE.md rule)
OUT="$BASE/TestFlight-fromstock"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$OUT/Loop-$STAMP.xcarchive"
EXPORT="$OUT/export-$STAMP"
LOG="$OUT/pipeline-$STAMP.log"

mkdir -p "$OUT"
note() { print -- "$(date +%H:%M:%S) $1" | tee -a "$LOG" }

# TEST GATE (coverage plan item 1). The ship script is the one choke point every build
# passes through — we commit locally and never push, so GitHub CI would test stale code.
# Deliberately scoped to the Sport-Mode suites: the full LoopTests target carries upstream
# tests we neither own nor keep green, and a gate that is routinely red gets disabled.
# ~7 s for 111 tests; skip only with SKIP_TESTS=1 for an emergency ship, which is logged.
SIM_ID="BE1EB8F5-C98F-472D-B910-858C3F2F9632"   # iPhone sim; `xcrun simctl list devices` if it goes stale
# Each attempt writes to its OWN log first, then appends to the pipeline log. The diagnostic
# greps below read RUNLOG, so they describe THE LAST ATTEMPT ONLY. Reading the appended
# pipeline log instead (as this did before 2026-08-12) makes a retry's diagnostics include
# the first attempt's failures — i.e. a green retry still prints failures, which is exactly
# the kind of lying output that gets a gate distrusted.
RUNLOG="$OUT/.gate-run.log"
run_test_gate() {
  : > "$RUNLOG"
  local rc=0
  xcodebuild \
    -workspace "$ROOT/LoopWorkspace.xcworkspace" \
    -scheme LoopWorkspace \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -derivedDataPath "$BASE/.dd-sim" \
    ONLY_ACTIVE_ARCH=YES \
    test \
    -only-testing:LoopTests/LoanProtocolV2Tests \
    -only-testing:LoopTests/LoanBooksHarnessTests \
    -only-testing:LoopTests/LoanEventJournalTests \
    -only-testing:LoopTests/WatchStoreEffectsTests \
    -only-testing:LoopTests/PodLoanPhoneControllerTests \
    -only-testing:LoopTests/WatchDosingLimitsTests \
    -only-testing:LoopTests/WatchOverrideDosingTests \
    -only-testing:LoopTests/LoanTwoSidedContractTests \
    >>"$RUNLOG" 2>&1 || rc=$?
  cat "$RUNLOG" >> "$LOG"
  return $rc
}

# Assertion failures in the log, if any. Every grep is `|| true`: under `set -e` a
# non-matching grep exits 1 and would abort the caller BEFORE `exit 67`, losing both the
# diagnostic and the exit code (found by sabotage-testing this gate on 2026-08-11 — it
# printed nothing at all). CoreData's "unable to open database file" chatter appears in
# GREEN runs too (54-68 lines), so it is filtered out.
gate_assertions() {
  grep -E "XCTAssert.* failed|: error:|failed - " "$RUNLOG" | grep -v CoreData | tail -20 || true
}

# Names of the test methods that failed in the last attempt.
failing_tests() {
  grep -oE "Test Case '-\[LoopTests\.[A-Za-z0-9_]+ [A-Za-z0-9_]+\]' failed" "$RUNLOG" \
    | sed -E "s/.* ([A-Za-z0-9_]+)\]' failed/\1/" | sort -u || true
}

# #103: the temp Core Data store intermittently answers with ZERO ROWS (~1 run in 6 as of
# 2026-08-12). The mechanism is not known — the two obvious hypotheses are ruled out, see
# docs/TEST_COVERAGE_PLAN.md. These are the tests it has surfaced in; all of them assert on
# store contents, which is the symptom.
#
# WHY A RETRY IS SAFE HERE, precisely: a deterministic regression in any of these tests
# CANNOT pass a retry. The only defect that could hide behind this is one that is itself
# intermittent at roughly the flake's own rate. That is a real if narrow exposure, so the
# retry is (a) restricted to this list, (b) required to come back FULLY green, and (c) loud
# in the log and tallied to a file, so a rising rate is visible rather than absorbed.
#
# Any failure outside this list exits immediately with no retry.
KNOWN_103_FLAKES=(testDuplicateBolusTwinDetection testHandbackSeamCloses testLedgerMatchesDoseStoreIOB)

only_known_103_flakes() {
  local t found=0
  while read -r t; do
    [[ -z "$t" ]] && continue
    found=1
    [[ " ${KNOWN_103_FLAKES[*]} " == *" $t "* ]] || return 1
  done <<< "$(failing_tests)"
  (( found == 1 ))
}

if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
  note "TEST GATE SKIPPED (SKIP_TESTS=1) — shipping unverified code by explicit request"
else
  note "TEST GATE starting (Sport Mode suites)"
  if ! run_test_gate; then
    if [[ -n "$(gate_assertions)" ]]; then
      if only_known_103_flakes; then
        note "TEST GATE: only known #103 flakes failed: $(failing_tests | tr '\n' ' ')"
        note "  #103 = the temp Core Data store intermittently answers with zero rows."
        note "  Retrying ONCE, and the retry must be FULLY green. A deterministic regression"
        note "  in these tests cannot pass a retry; only an intermittent one could hide here."
        print -- "$(date '+%Y-%m-%d %H:%M:%S') $(failing_tests | tr '\n' ' ')" >> "$OUT/flake-tally.log"
        note "  #103 occurrences recorded to date: $(wc -l < "$OUT/flake-tally.log" | tr -d ' ') (tally: $OUT/flake-tally.log)"
        note "  If this rate climbs, STOP retrying and find the mechanism."
        xcrun simctl shutdown all >/dev/null 2>&1 || true
        if ! run_test_gate; then
          note "TEST GATE FAILED ON RETRY — NOT archiving. This is NOT the flake:"
          print -- "$(gate_assertions)"
          exit 67
        fi
        note "TEST GATE ok on retry — first attempt was the #103 flake"
      else
        note "TEST GATE FAILED — NOT archiving. Assertion failures:"
        print -- "$(gate_assertions)"
        exit 67
      fi
    else
    # No assertion lines at all = the run never got far enough to assert. The simulator
    # runner hanging before connection is a KNOWN environment flake — four occurrences on
    # 2026-08-11 (343/343/381/372 s, vs ~6 s green) with no code change between them.
    # Retry ONCE. This cannot mask a real failure: we only get here when the log contains
    # zero assertion failures, and a second run that produces any will exit below.
      note "No assertion failures — looks like the simulator, not your code:"
      grep -A3 "^Testing failed:" "$RUNLOG" | tail -6 || true
      note "Retrying once after shutting the simulators down..."
      xcrun simctl shutdown all >/dev/null 2>&1 || true
      if ! run_test_gate; then
        note "TEST GATE FAILED on retry — NOT archiving."
        if [[ -n "$(gate_assertions)" ]]; then
          note "Assertion failures:"
          print -- "$(gate_assertions)"
        else
          note "Still no assertion failures — the test runner is not starting. Check Xcode/simulator state."
          grep -A3 "^Testing failed:" "$RUNLOG" | tail -6 || true
        fi
        exit 67
      fi
      note "TEST GATE ok on retry (first attempt was an environment flake)"
    fi
  fi
  note "TEST GATE ok — $(grep -oE 'Executed [0-9]+ tests, with [0-9]+ failures' "$LOG" | tail -1 || true)"
fi

note "ARCHIVE starting (LoopWorkspace scheme, Release) — the long step; log: $LOG"
caffeinate -is xcodebuild \
  -workspace "$ROOT/LoopWorkspace.xcworkspace" \
  -scheme LoopWorkspace \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  archive >>"$LOG" 2>&1 || { note "ARCHIVE FAILED — last lines:"; grep -B2 -A6 "error:" "$LOG" | tail -40 || tail -40 "$LOG"; exit 65; }
note "ARCHIVE ok: $ARCHIVE"

if [[ "${1:-}" == "--archive-only" ]]; then
  note "Stopping before upload (--archive-only)."
  exit 0
fi

note "UPLOAD starting (destination=upload; ASC assigns the next build number)"
caffeinate -is xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/Scripts/ExportOptionsTestFlight.plist" \
  -exportPath "$EXPORT" \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -allowProvisioningUpdates >>"$LOG" 2>&1 || { note "UPLOAD FAILED — last lines:"; grep -B2 -A6 "error:" "$LOG" | tail -40 || tail -40 "$LOG"; exit 66; }
note "UPLOAD ok — App Store Connect is processing; TestFlight notifies when installable."

# Keep the three newest archives; old ones are gigabytes each.
ls -dt "$OUT"/Loop-*.xcarchive 2>/dev/null | tail -n +4 | while read -r old; do
  note "pruning old archive: ${old:t}"
  rm -rf "$old"
done
