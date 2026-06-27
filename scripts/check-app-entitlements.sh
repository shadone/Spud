#!/usr/bin/env bash
#
# Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Release pre-flight: verify a built/signed Spud app carries the entitlements it
# needs at RUNTIME. A release archived with CODE_SIGNING_ALLOWED=NO (or otherwise
# mis-signed at export) silently drops these. The damage is severe and invisible
# to the simulator + tests:
#   - the app crashes at launch (AppDatabase throws appGroupContainerUnavailable,
#     DependencyContainer.init fatalErrors), and
#   - iOS clears the App Group container on install (deleting the on-disk DB),
#     so users lose their local data and land on onboarding.
# Build 12 shipped exactly this. Run this gate on the ARCHIVE and the exported
# IPA before `asc builds upload`; a non-zero exit must block the release.
#
# Usage: scripts/check-app-entitlements.sh <path>
#   <path> may be a .app, an .xcarchive, or an .ipa.

set -euo pipefail

readonly REQUIRED_APP_GROUP="group.info.ddenis.Spud.shared"
# keychain-access-groups is team-prefixed (e.g. J8B76VBZ57.info.ddenis.Spud.shared),
# so match by suffix; the leading "group." app-group value must NOT satisfy it.
readonly REQUIRED_KEYCHAIN_SUFFIX=".info.ddenis.Spud.shared"

input="${1:-}"
if [ -z "$input" ]; then
    echo "usage: $(basename "$0") <.app|.xcarchive|.ipa>" >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

resolve_app() {
    case "$1" in
    *.app)
        printf '%s\n' "$1"
        ;;
    *.xcarchive)
        find "$1/Products/Applications" -maxdepth 1 -name '*.app' | head -1
        ;;
    *.ipa)
        (cd "$tmp" && unzip -q "$1")
        find "$tmp/Payload" -maxdepth 1 -name '*.app' | head -1
        ;;
    *)
        echo "FAIL: unsupported input (need .app / .xcarchive / .ipa): $1" >&2
        exit 2
        ;;
    esac
}

app="$(resolve_app "$input")"
if [ -z "$app" ] || [ ! -d "$app" ]; then
    echo "FAIL: no .app found in: $input" >&2
    exit 2
fi

ent="$tmp/entitlements.plist"
if ! codesign -d --entitlements "$ent" --xml "$app" 2>/dev/null; then
    # Older codesign without --xml; fall back to the raw form.
    if ! codesign -d --entitlements "$ent" "$app" 2>/dev/null; then
        echo "FAIL: $app is not signed / has no entitlements" >&2
        exit 1
    fi
fi

fail=0

app_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$ent" 2>/dev/null || true)"
if [ "$app_group" != "$REQUIRED_APP_GROUP" ]; then
    # PlistBuddy can choke on a codesign blob header; fall back to a string scan.
    if ! grep -aq "$REQUIRED_APP_GROUP" "$ent"; then
        echo "FAIL: missing App Group entitlement '$REQUIRED_APP_GROUP'." >&2
        echo "      The app would crash at launch and iOS would wipe its container." >&2
        echo "      Did you archive with CODE_SIGNING_ALLOWED=NO? Archive WITH signing." >&2
        fail=1
    fi
fi

# Require a keychain-access-group ending in the shared suffix that is NOT the
# "group." app-group value (which also ends in the suffix).
if ! grep -aoE '[A-Za-z0-9.]+\.info\.ddenis\.Spud\.shared' "$ent" 2>/dev/null \
    | grep -v '^group\.' | grep -q "$REQUIRED_KEYCHAIN_SUFFIX"; then
    echo "FAIL: missing keychain-access-group '<TEAM>$REQUIRED_KEYCHAIN_SUFFIX'." >&2
    echo "      Account/keychain access would break." >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "Entitlement check FAILED for: $app" >&2
    exit 1
fi

echo "Entitlement check OK: $(basename "$app") has the App Group + keychain entitlements."
