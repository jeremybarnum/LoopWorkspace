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
# Signing: cloud signing via the Xcode-logged-in account (-allowProvisioningUpdates).
# Outputs live OUTSIDE the repo in ../TestFlight-fromstock (archives pruned to 3).

set -euo pipefail

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
  -allowProvisioningUpdates >>"$LOG" 2>&1 || { note "UPLOAD FAILED — last lines:"; grep -B2 -A6 "error:" "$LOG" | tail -40 || tail -40 "$LOG"; exit 66; }
note "UPLOAD ok — App Store Connect is processing; TestFlight notifies when installable."

# Keep the three newest archives; old ones are gigabytes each.
ls -dt "$OUT"/Loop-*.xcarchive 2>/dev/null | tail -n +4 | while read -r old; do
  note "pruning old archive: ${old:t}"
  rm -rf "$old"
done
