# Spud — project generation
#
# The Xcode project (Spud.xcodeproj) is generated from project.yml via XcodeGen
# and is gitignored. project.yml is the source of truth. Regenerate after pulling
# changes to project.yml or adding/removing source files.

.PHONY: project release-project bootstrap explorer-seed safari-matches verify-archive verify-ipa

# Regenerate Spud.xcodeproj from project.yml.
project:
	xcodegen generate

# Regenerate Spud.xcodeproj for a TestFlight / App Store archive: same as
# `project` but with test-only dependencies removed (everything between the
# `# >>> release-strip` / `# <<< release-strip` sentinels in project.yml).
# Shipping SBTUITestTunnelServer links a private API and is rejected with
# ITMS-90338, so use this target — not `project` — before archiving to distribute.
release-project:
	sed '/# >>> release-strip/,/# <<< release-strip/d' project.yml > .project.release.yml
	xcodegen generate --spec .project.release.yml
	rm -f .project.release.yml

# Regenerate the bundled Lemmy Explorer seed (instances + communities) from
# data.lemmyverse.net into SpudDataKit/Resources. Run per release.
explorer-seed:
	swift scripts/generate-explorer-seed.swift

# Regenerate the "Open in Spud" Safari content-script allowlist from the bundled
# Explorer instance seed. Run after `make explorer-seed`.
safari-matches:
	swift scripts/generate-safari-matches.swift

# First-time / fresh-checkout setup: install pinned CLI tools (SwiftFormat,
# SwiftGen) via Mint, then generate the Xcode project.
bootstrap:
	mint bootstrap
	xcodegen generate

# Release pre-flight entitlement gate. A release archived with
# CODE_SIGNING_ALLOWED=NO (or otherwise mis-signed at export) silently drops the
# App Group / keychain entitlements; the app then crashes at launch AND iOS wipes
# its container, deleting user data (build 12 shipped exactly this). Run BOTH the
# archive and the exported IPA through this gate before `asc builds upload` — a
# non-zero exit must block the upload.
#   make verify-archive ARCHIVE=.asc/artifacts/Spud.xcarchive
#   make verify-ipa     IPA=.asc/artifacts/Spud.ipa
verify-archive:
	scripts/check-app-entitlements.sh "$(ARCHIVE)"

verify-ipa:
	scripts/check-app-entitlements.sh "$(IPA)"
