#!/bin/sh
# Resolve an xcodebuild -destination for simulator test runs, encoding the
# rules that used to live as prose in CLAUDE.md:
#   - If a simulator is already booted, target it BY ID (never boot a second
#     sim by name: two booted sims cause "SBMainWorkspace Busy" test failures).
#   - Otherwise resolve the reference device (iPhone 17 Pro) on the newest
#     iOS 26.3.x runtime by UUID (the OS string alone drifts across minor
#     runtime updates: 26.3 vs 26.3.1).
#   - With --reference, additionally FAIL if the booted sim is not the
#     reference device: app-level snapshot references only match on
#     iPhone 17 Pro / iOS 26.3.x.
#
# Prints "platform=iOS Simulator,id=<UUID>" on stdout; exits non-zero with a
# hint on stderr if no suitable simulator exists.

set -eu

want_reference=false
[ "${1:-}" = "--reference" ] && want_reference=true

devices=$(xcrun simctl list devices)

booted_line=$(printf '%s\n' "$devices" | grep "(Booted)" | head -1 || true)
if [ -n "$booted_line" ]; then
    booted_id=$(printf '%s\n' "$booted_line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
    if $want_reference; then
        case "$booted_line" in
            *"iPhone 17 Pro ("*) ;;
            *)
                echo "error: booted simulator is not the snapshot reference device (iPhone 17 Pro)." >&2
                echo "hint: shut it down (xcrun simctl shutdown all) or boot the reference sim first." >&2
                exit 1
                ;;
        esac
    fi
    echo "platform=iOS Simulator,id=$booted_id"
    exit 0
fi

# No booted sim: resolve the reference device on the newest 26.3.x runtime.
ref_id=$(printf '%s\n' "$devices" \
    | awk '/-- iOS 26\.3/{run=1; next} /^--/{run=0} run && /iPhone 17 Pro \(/ {print}' \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1 || true)
if [ -z "$ref_id" ]; then
    echo "error: no iPhone 17 Pro simulator on an iOS 26.3.x runtime found." >&2
    echo "hint: xcrun simctl list devices | grep 'iPhone 17 Pro'" >&2
    exit 1
fi
echo "platform=iOS Simulator,id=$ref_id"
