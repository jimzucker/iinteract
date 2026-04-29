#!/usr/bin/env bash
# Run the iInteract test suite against each platform the app ships on:
# iPhone (iOS), iPad (iPadOS), and Mac Catalyst.
#
# Usage:
#   ./scripts/test-matrix.sh                # all destinations
#   ./scripts/test-matrix.sh iphone         # iPhone only
#   ./scripts/test-matrix.sh ipad           # iPad only
#   ./scripts/test-matrix.sh catalyst       # Mac Catalyst only (build-only)
#   ./scripts/test-matrix.sh watch          # watchOS only (logic-only tests)
#   ./scripts/test-matrix.sh fast           # iPhone only (alias for the local-dev inner loop)
#
# Local dev: use `fast`. CI: run with no args.
#
# Why this script exists:
# - The codebase ships on iOS (iPhone + iPad) and Mac Catalyst, but the
#   default `xcodebuild ... test` only targets one destination. Without
#   explicitly running the matrix, conditional-compilation drift between
#   platforms (UIKit vs Mac Catalyst, iPad popovers, etc.) ships unverified.
# - watchOS has no test target — the watch app is small enough that
#   manual smoke testing is the right cost-benefit ratio. If watch test
#   coverage becomes important, add an `iInteractWatchTests` target and
#   extend this script.

set -euo pipefail

SCHEME="iInteract"
WATCH_SCHEME="iInteractWatch"

# Pick destination variants Jim's machine has handy. Adjust the OS pin
# if you upgrade Xcode and the simulators move. `xcodebuild -showdestinations
# -scheme iInteract` lists what's currently installed.
IPHONE_DEST='platform=iOS Simulator,name=iPhone 16,OS=18.2'
IPAD_DEST='platform=iOS Simulator,name=iPad (10th generation),OS=18.2'
CATALYST_DEST='platform=macOS,variant=Mac Catalyst'
WATCH_DEST='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'

run_dest() {
    local label="$1"
    local destination="$2"
    echo
    echo "=== Testing on $label ==="
    echo "    destination: $destination"
    xcodebuild -scheme "$SCHEME" -destination "$destination" test \
        | grep -E "Test Suite|Executed.*tests|TEST (SUCCEEDED|FAILED)|error:|FAILED" \
        | tail -30
}

# Mac Catalyst runs the unit suite only — UI tests would need a Mac
# variant of the iInteractUITests provisioning profile (the bundle
# identifier `com.zucker.iInteract.UITests` only has iOS), and
# Catalyst UI tests would just verify "iPhone-shaped UI renders in a
# Mac window" which Apple's runtime already does. `-only-testing` on
# the Catalyst run skips the UI test bundle's Run phase. The UI test
# target still builds (Xcode prevalidates the whole scheme) — it
# signs cleanly because we've set DEVELOPMENT_TEAM on it.
run_dest_unit_only() {
    local label="$1"
    local destination="$2"
    echo
    echo "=== Testing on $label (unit suite only) ==="
    echo "    destination: $destination"
    xcodebuild -scheme "$SCHEME" -destination "$destination" \
        -only-testing:iInteractTests test \
        | grep -E "Test Suite|Executed.*tests|TEST (SUCCEEDED|FAILED)|error:|FAILED" \
        | tail -30
}

case "${1:-all}" in
    fast|iphone)
        run_dest "iPhone simulator" "$IPHONE_DEST"
        ;;
    ipad)
        run_dest "iPad simulator" "$IPAD_DEST"
        ;;
    catalyst|mac)
        run_dest_unit_only "Mac Catalyst" "$CATALYST_DEST"
        ;;
    watch)
        echo
        echo "=== Testing on watchOS Simulator ==="
        echo "    destination: $WATCH_DEST"
        xcodebuild -scheme "$WATCH_SCHEME" -destination "$WATCH_DEST" test \
            | grep -E "Test Suite|Executed.*tests|TEST (SUCCEEDED|FAILED)|error:|FAILED" \
            | tail -20
        ;;
    all|"")
        run_dest "iPhone simulator" "$IPHONE_DEST"
        run_dest "iPad simulator"   "$IPAD_DEST"
        run_dest_unit_only "Mac Catalyst" "$CATALYST_DEST"
        echo
        echo "=== Testing on watchOS Simulator ==="
        echo "    destination: $WATCH_DEST"
        xcodebuild -scheme "$WATCH_SCHEME" -destination "$WATCH_DEST" test \
            | grep -E "Test Suite|Executed.*tests|TEST (SUCCEEDED|FAILED)|error:|FAILED" \
            | tail -20
        ;;
    *)
        echo "Unknown target: $1" >&2
        echo "Usage: $0 [iphone|ipad|catalyst|all|fast]" >&2
        exit 1
        ;;
esac
