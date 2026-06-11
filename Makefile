# Spud — project generation
#
# The Xcode project (Spud.xcodeproj) is generated from project.yml via XcodeGen
# and is gitignored. project.yml is the source of truth. Regenerate after pulling
# changes to project.yml or adding/removing source files.

.PHONY: project bootstrap

# Regenerate Spud.xcodeproj from project.yml.
project:
	xcodegen generate

# First-time / fresh-checkout setup: install pinned CLI tools (SwiftFormat,
# SwiftGen) via Mint, then generate the Xcode project.
bootstrap:
	mint bootstrap
	xcodegen generate
