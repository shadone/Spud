#!/bin/sh

# Xcode Cloud post-clone step.
#
# Spud's Xcode project is generated from project.yml by XcodeGen and is NOT
# committed to git (see .gitignore). Xcode Cloud clones only the repository, so
# the project must be regenerated here before the build action runs. The build
# also has a SwiftGen pre-build phase that shells out to `mint run swiftgen`, so
# Mint and the pinned tools from the Mintfile must be available on PATH.

set -e

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

echo "==> Installing build tooling (mint, xcodegen)"
brew install mint xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "==> Bootstrapping Mint packages (SwiftFormat, SwiftGen) from Mintfile"
mint bootstrap --link

echo "==> Generating Spud.xcodeproj from project.yml"
xcodegen generate

echo "==> Post-clone setup complete"
