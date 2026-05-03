# Spud — native iOS app for Lemmy

Spud (placeholder name) is a UIKit client for [Lemmy](https://join-lemmy.org), the federated link aggregator.

## Workspace layout

The Xcode workspace lives one directory up and stitches this repo together with [LemmyKit](../LemmyKit), the OpenAPI-generated Lemmy client used by the app. **Always open `Spud.xcworkspace`**, not the bare `Spud.xcodeproj`.

```
info.ddenis/Spud/
├── Spud.xcworkspace            ← open this
├── Spud/                       ← this repo (iOS app)
└── LemmyKit/                   ← sibling SPM package
```

## Targets

- **`Spud`** — the iOS application (UIKit, coordinators, view models)
- **`SpudWidgetExtension`** — home-screen widget showing top posts
- **`OpenInAppExtension`** — share/action extension to open Lemmy URLs in Spud
- **`SpudDataKit`** — domain layer: Core Data store, Lemmy services, scheduler, image loading
- **`SpudUIKit`** — design tokens, color/symbol resources, SwiftGen-generated assets
- **`SpudUtilKit`** — Foundation extensions and small utilities (`Atomic`, `UserDefaultsBacked`, `Logger`)
- Test targets: `SpudTests`, `SpudDataKitTests`, `SpudUtilKitTests`, `SpudSnapshotTests`, `SpudUITests`

The app and its extensions share keychain group `info.ddenis.Spud.shared` and app group `group.info.ddenis.Spud.shared`.

## Development setup

### Install `mint`

We use [mint](https://github.com/yonaskolb/Mint) to run Swift CLI tools (SwiftFormat, SwiftGen) at versions pinned in `Mintfile`.

```sh
brew install mint
mint bootstrap
```

### Install the pre-commit hook

The hook keeps `Spud.xcodeproj/project.pbxproj` deterministically sorted. See [scripts/git-hooks/README.md](scripts/git-hooks/README.md):

```sh
ln -sf ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit
```

### Build

```sh
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

### Test

Unit + UI tests (`Spud.xctestplan`):

```sh
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test
```

Snapshot tests (`SpudSnapshots.xctestplan`) use [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing). They are sensitive to simulator and orientation:

> **Run on iPhone 14 Pro simulator in portrait orientation.** Reference images are recorded against this exact configuration.

```sh
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test
```

## Notable dependencies

Resolved via SPM (see `Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`):

- [LemmyKit](../LemmyKit) — local sibling package, OpenAPI-generated Lemmy API client
- [Down](https://github.com/johnxnguyen/Down) — Markdown rendering
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) — keychain wrapper
- [SemVer](https://github.com/glwithu06/Semver.swift) — Lemmy server version comparisons
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — snapshot tests
- [SBTUITestTunnel](https://github.com/Subito-it/SBTUITestTunnel) — UI test stubbing

## For Claude Code sessions

Working notes, conventions, and the upgrade-pickup checklist live in [CLAUDE.md](CLAUDE.md).

## License

Spud is licensed under a 2-clause BSD license. See [LICENSE](LICENSE).
