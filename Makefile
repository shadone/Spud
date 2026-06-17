# Spud — project generation
#
# The Xcode project (Spud.xcodeproj) is generated from project.yml via XcodeGen
# and is gitignored. project.yml is the source of truth. Regenerate after pulling
# changes to project.yml or adding/removing source files.

.PHONY: project bootstrap explorer-seed safari-matches

# Regenerate Spud.xcodeproj from project.yml.
project:
	xcodegen generate

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
