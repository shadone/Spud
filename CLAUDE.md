# Spud — Claude Code working notes

Native iOS client for [Lemmy](https://join-lemmy.org). UIKit, Core Data, SPM. Bundle ID `info.ddenis.Spud`, team `J8B76VBZ57`.

Project went dormant after June 2024. Picked back up May 2026. The previous session was mid-migration to Swift strict concurrency (project flag `SWIFT_STRICT_CONCURRENCY = complete` is already set); that WIP lives in `git stash@{0}` (`pre-pickup-2026-05 strict-concurrency WIP`) but is intentionally being redone from scratch — do not pop it without asking.

## Workspace layout

The Xcode workspace is the parent directory's `Spud.xcworkspace`, which references two checkouts side-by-side:

```
info.ddenis/Spud/
├── Spud/                       ← this repo (the iOS app)
│   └── Spud.xcodeproj
└── LemmyKit/                   ← sibling SPM package, OpenAPI-generated Lemmy client
```

Always open `Spud.xcworkspace`, not the bare `Spud.xcodeproj`. The workspace also contains older sibling checkouts (`Lemmy-OpenAPI-Spec`, `Lemmy-Swift-Client`, `DiasporaNodeInfo`, `Down`, `OpenInApolloExtension`) — those are historical/unused at the workspace level; LemmyKit is the live one.

## Targets

| Target | Type | Purpose |
|---|---|---|
| `Spud` | iOS app | Main app — UIKit scenes, coordinators, view models |
| `SpudWidgetExtension` | App extension | Home-screen widget showing top posts |
| `OpenInAppExtension` | App extension | "Open in Spud" share/action extension |
| `SpudDataKit` | Framework | Domain layer — Core Data store, Lemmy services, scheduler, image service |
| `SpudUIKit` | Framework | Design tokens, color/symbol resources, SwiftGen-generated assets |
| `SpudUtilKit` | Framework | Foundation extensions, `UserDefaultsBacked`, `Atomic`, `Logger`, etc. |
| `SpudTests` / `SpudDataKitTests` / `SpudUtilKitTests` | Unit tests | Per-framework |
| `SpudSnapshotTests` | Snapshot tests | Uses `pointfreeco/swift-snapshot-testing` — locked to **iPhone 14 Pro, portrait** |
| `SpudUITests` | UI tests | Uses `SBTUITestTunnel` for in-app stubbing |

App + extensions share keychain group `info.ddenis.Spud.shared` and app group `group.info.ddenis.Spud.shared`. The widget reads its data via `SpudDataKit` services configured against the shared container.

Dependency direction: `Spud` → `SpudDataKit` → `SpudUtilKit`; `Spud` → `SpudUIKit` → `SpudUtilKit`. Frameworks must not import the app target.

## Schemes & test plans

- `Spud.xcscheme` — primary; uses `Spud.xctestplan` (Spud + SpudDataKit + SpudUtilKit + UI tests)
- `SpudDataKit.xcscheme` — framework dev loop
- `SpudWidgetExtension.xcscheme` — widget dev loop
- `SpudUITests.xcscheme` — UI tests in isolation
- `SpudSnapshots.xctestplan` — snapshot tests only; **must run on iPhone 14 Pro simulator in portrait**, otherwise reference images won't match

## Core Data

Single model: `SpudDataKit/Services/DataStore/DataStore.xcdatamodeld/Spud.xcdatamodel` (no version migrations yet — only one model version exists). Entities live in `SpudDataKit/Services/DataStore/Models/` as plain Swift files (manual `@NSManaged` properties, not codegen). Top-level entities: `Instance`, `LemmySite`, `LemmyAccount`, `LemmyCommunity`, `LemmyPerson`, `LemmyPost`, `LemmyComment`, `LemmyFeed`, `LemmyPage`, plus `*Info` companions and element rows. Adding a new model version requires creating a new `.xcdatamodel` inside the `.xcdatamodeld` bundle and setting it as current.

## Build & test

```sh
# One-time
brew install mint
mint bootstrap                            # SwiftFormat + SwiftGen pinned by Mintfile
ln -sf ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit

# Build (workspace, not project)
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# Unit tests
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test

# Snapshot tests — iPhone 14 Pro is required
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test
```

The pre-commit hook runs `scripts/sort-Xcode-project-file.pl` to keep `project.pbxproj` deterministic. Don't bypass it.

## Code style

- `.swiftformat` is authoritative — SwiftFormat (pinned in `Mintfile`) runs via the pre-commit hook
- `.swift-version` is the Swift toolchain pin; project-level `SWIFT_VERSION` in `pbxproj` should match
- No emojis in code, comments, docs, or commit messages
- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`)
- Small, focused commits; split unrelated changes
- Prefer many small files over few large ones

## Strict concurrency

`SWIFT_STRICT_CONCURRENCY = complete` is already on at the project level. The earlier WIP attempted to silence the resulting warnings ad-hoc (saw commits like "Added a hack to silence strict concurrency warning", "Quick fix for strict concurrency warnings"). The fresh approach should be Swift 6 language mode end-to-end: explicit `Sendable` annotations, actor-isolated services, no `@unchecked` escape hatches unless the invariant is documented. LemmyKit already enables `StrictConcurrency` and `DisableOutwardActorInference`.

## Pickup checklist (May 2026)

Follow this order — each step assumes the previous landed cleanly. Most need Xcode running to validate; do not edit `project.pbxproj` blindly from the CLI.

1. **Toolchain alignment**
   - Confirm Xcode version (16.x or 17.x) and matching command-line tools.
   - Run `mint bootstrap` against the updated `Mintfile` (SwiftFormat is on 0.61.1; SwiftGen stays on 6.6.3 — that's the current latest).
   - Decide Swift language mode. Today: `.swift-version = 5.9`, `pbxproj SWIFT_VERSION = 5.0` (mismatch). For Swift 6 strict concurrency end-to-end, set both to `6.0` and switch each target's `SWIFT_VERSION` build setting in Xcode.
2. **Deployment target bump**
   - Currently mixed across targets: `15.0` / `15.2` / `16.0`. Pick a single floor (likely `iOS 17` given current device share) and apply via Xcode → Project → Info → iOS Deployment Target. Re-test on simulator.
3. **SPM resolution**
   - `Package.resolved` (in `Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`) was last refreshed mid-2024. Run File → Packages → Update to Latest Versions inside Xcode and review the diff.
4. **LemmyKit regeneration**
   - LemmyKit and `Lemmy-OpenAPI-Spec` were last touched July 2025. Pull current Lemmy server OpenAPI spec, regenerate, re-resolve the package, fix any breaking-change call sites in `SpudDataKit/Services/Lemmy/`.
5. **Strict concurrency, fresh pass**
   - Project flag is already `complete`. Don't reuse the stashed WIP. Walk targets bottom-up: `SpudUtilKit` → `SpudUIKit` → `SpudDataKit` → `Spud` / `SpudWidget` / `OpenInAppExtension`. For each, drive warnings to zero before moving up. Prefer `actor` for mutable services, explicit `Sendable` annotations on DTOs, isolated `@MainActor` for view models. No `@unchecked Sendable` without a documented invariant.
6. **Snapshot test refresh**
   - After any deployment-target / iOS SDK change, snapshot references will drift. Re-record on iPhone 14 Pro simulator, portrait. If switching to a newer reference device, do it as one deliberate commit and update this file + README.
7. **Optional housekeeping**
   - `Spud.coredataproj` at the repo parent is from the old Core Data Editor app — verify still useful or delete.
   - JPGs at the repo parent (`3072d3c8-…`, `d8a1f433-…`, etc.) look like stray screenshots — confirm and remove.
   - Add `CHANGELOG.md` / `CONTRIBUTING.md` if/when the project goes public.

See [README.md](README.md) for the user-facing overview.
