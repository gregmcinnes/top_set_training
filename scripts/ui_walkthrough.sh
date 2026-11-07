#!/bin/zsh
# Run the UI walkthrough from a clean install on a spare simulator, writing screenshots
# to a directory to read afterwards. It uninstalls the app and logs real sets, so never
# point it at a simulator whose data matters.
#
#   scripts/ui_walkthrough.sh [output-dir] [simulator-id] [test-filter]
#
# test-filter narrows the run, e.g. WorkoutSessionUITests/testKillMidRestResumesTheCountdown
set -u

OUT="${1:-${TMPDIR:-/tmp}/topset-walkthrough}"
SIM="${2:-2E75F8F8-45EF-4917-9B92-4447E0148232}"  # A spare iPhone 16
FILTER="${3:-}"
BOOTED_MAIN="4224FF3E-B0E2-4F3A-A163-761E47FA8167"

if [[ "$SIM" == "$BOOTED_MAIN" ]]; then
    echo "Refusing to run on Greg's simulator: this wipes the app's data." >&2
    exit 1
fi

cd "$(dirname "$0")/.." || exit 1
mkdir -p "$OUT"

xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl uninstall "$SIM" com.gregorymcinnes.topsettraining 2>/dev/null

ONLY="SBSUITests"
[[ -n "$FILTER" ]] && ONLY="SBSUITests/$FILTER"

TEST_RUNNER_WALKTHROUGH_OUT="$OUT" xcodebuild test \
    -project SBS.xcodeproj -scheme SBSWalkthrough \
    -destination "platform=iOS Simulator,id=$SIM" \
    -only-testing:"$ONLY" 2>&1 \
    | grep -E "Test Case .*(passed|failed)|error:|Executed .* tests|\*\* (TEST|BUILD)"
STATUS=${pipestatus[1]}

echo "Screenshots: $OUT"
exit $STATUS
