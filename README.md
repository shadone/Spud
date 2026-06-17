# Spud — native iOS app for Lemmy

Spud (placeholder name) is a UIKit client for [Lemmy](https://join-lemmy.org), the federated link aggregator.

## Project layout

`Spud.xcodeproj` is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (run `make project`); the generated project is gitignored, so `project.yml` is the source of truth. [LemmyKit](https://github.com/shadone/LemmyKit), the OpenAPI-generated Lemmy client, is consumed as a versioned remote SPM package pinned to a release tag in `project.yml`, so the project resolves it from its git remote — no workspace needed.

```
info.ddenis/Spud/
├── Spud/                       ← this repo (iOS app); open Spud.xcodeproj
└── LemmyKit/                   ← dev checkout of the LemmyKit package (optional; Spud builds the pinned release)
```

## Targets

- **`Spud`** — the iOS application (UIKit, coordinators, view models)
- **`SpudWidgetExtension`** — home-screen widget showing top posts
- **`OpenInAppExtension`** — share/action extension to open Lemmy URLs in Spud
- **`SpudDataKit`** — domain layer: GRDB store, Lemmy services, scheduler, image loading
- **`SpudUIKit`** — design tokens, color/symbol resources, SwiftGen-generated assets
- **`SpudUtilKit`** — Foundation extensions and small utilities (`Atomic`, `UserDefaultsBacked`, `Logger`)
- Test targets: `SpudTests`, `SpudDataKitTests`, `SpudUtilKitTests`, `SpudSnapshotTests`, `SpudUITests`

The app and its extensions share keychain group `info.ddenis.Spud.shared` and app group `group.info.ddenis.Spud.shared`.

## Development setup

### Install tools and generate the project

We use [mint](https://github.com/yonaskolb/Mint) to run Swift CLI tools (SwiftFormat, SwiftGen) at versions pinned in `Mintfile`, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate `Spud.xcodeproj` from `project.yml`.

```sh
brew install mint xcodegen
make bootstrap        # mint bootstrap + xcodegen generate
```

Regenerate the project any time `project.yml` changes or sources are added/removed:

```sh
make project          # xcodegen generate
```

### Build

```sh
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Test

Unit + UI tests (`Spud.xctestplan`):

```sh
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Snapshot tests (`SpudSnapshots.xctestplan`) use [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing). They are sensitive to simulator and orientation:

> **Run on iPhone 14 Pro simulator in portrait orientation.** Reference images are recorded against this exact configuration.

```sh
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test
```

## Notable dependencies

Declared in [`project.yml`](project.yml) and resolved via SPM:

- [LemmyKit](https://github.com/shadone/LemmyKit) — OpenAPI-generated Lemmy API client (pinned remote package)
- [Down](https://github.com/johnxnguyen/Down) — Markdown rendering
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) — keychain wrapper
- [SemVer](https://github.com/glwithu06/Semver.swift) — Lemmy server version comparisons
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — snapshot tests
- [SBTUITestTunnel](https://github.com/Subito-it/SBTUITestTunnel) — UI test stubbing

## For Claude Code sessions

Working notes, conventions, and the upgrade-pickup checklist live in [CLAUDE.md](CLAUDE.md).

## License

Spud is licensed under a 2-clause BSD license. See [LICENSE](LICENSE).
