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

## Persistence

GRDB / SQLite, in `SpudDataKit/Services/AppDatabase/`. The DB lives at
`group.info.ddenis.Spud.shared/AppDatabase/AppDatabase.sqlite` — App Group
container so the widget and extensions read the same database.

Schema migrations are GRDB `DatabaseMigrator` registrations in
`AppDatabase+Migrations.swift`. Add a new migration as the next case;
don't edit existing ones.

Records live in `SpudDataKit/Services/AppDatabase/Records/` (one file per
GRDB record type: `AccountRecord`, `SiteRecord`, `PostRecord`, etc).
Importers (`Importers/*Importer.swift`) translate Lemmy API responses
into upserts. Read-side helpers (`Observations.swift`,
`*Observations.swift`, `*Queries.swift`) expose AsyncStreams and one-shot
sync reads.

Core Data was demolished in Stage 7 (May 2026). `LemmyAccount` /
`LemmySite` / etc. and `DataStore` no longer exist; the durable account
identifier is `accountKeychainId: String`.

## Build & test

```sh
# One-time
brew install mint
mint bootstrap                            # SwiftFormat + SwiftGen pinned by Mintfile
ln -sf ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit

# Build (workspace, not project). The agentic build_and_test.py wrapper expects
# --simulator "iPhone 17 Pro" — match that here unless you know a 15 Pro is installed.
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Unit tests
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Snapshot tests — iPhone 14 Pro is required
xcodebuild -workspace ../Spud.xcworkspace -scheme Spud \
  -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test

# Faster build path used in agentic sessions — incremental, parses errors/warnings,
# supports --json. Fall back to xcodebuild only if you need flags it doesn't expose.
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/ios-simulator-skill/scripts/build_and_test.py --scheme Spud
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/ios-simulator-skill/scripts/build_and_test.py --scheme SpudWidgetExtension
```

The pre-commit hook runs `scripts/sort-Xcode-project-file.pl` to keep `project.pbxproj` deterministic. Don't bypass it.

## Code style

- `.swiftformat` is authoritative — SwiftFormat (pinned in `Mintfile`) runs via the pre-commit hook
- SwiftFormat invocation: `mint run swiftformat <paths>` (pre-commit hook runs in lint mode only — format before staging)
- `.swift-version` is the Swift toolchain pin; project-level `SWIFT_VERSION` in `pbxproj` should match
- Default branch is `main` (overrides the global "source repos use `develop`" preference)
- No emojis in code, comments, docs, or commit messages
- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`)
- Small, focused commits; split unrelated changes
- Prefer many small files over few large ones
- Inside `Task { [weak self] ... guard let self else { return } ... }`, drop the `self.` prefix on subsequent property writes — SwiftFormat's `redundantSelf` rule flags it

## Tooling quirks

- SourceKit "No such module" diagnostics in editor tooling are unreliable here — trust `build_and_test.py` over IDE squiggles.
- Editing `Spud.xcodeproj/project.pbxproj` from Python: `pbxproj`'s `remove_file_by_id` assumes every `PBXBuildFile` has `fileRef`, but SPM product refs use `productRef`. Monkey-patch with a `getattr(build_file, 'fileRef', None) or getattr(build_file, 'productRef', None)` fallback before calling.
- Pre-commit hook runs `scripts/sort-Xcode-project-file.pl` automatically; never bypass with `--no-verify`.
- XCResult bundles from `build_and_test.py` live at `~/.ios-simulator-skill/xcresults/xcresult-<ts>.xcresult`. Get detailed test failure messages with `xcrun xcresulttool get test-results tests --path <bundle> --compact` — the wrapper's own `--get-errors` / `--get-warnings` only surfaces build issues, not test assertion text.

## Strict concurrency

`SWIFT_STRICT_CONCURRENCY = complete` is on at the project level. Every shipped target — Spud, SpudDataKit, SpudWidgetExtension, OpenInAppExtension, SpudUtilKit, SpudUIKit — and SpudDataKitTests are at Swift 6.0 language mode. SpudTests, SpudUITests, and SpudSnapshotTests remain at 5.0 (they're stubs / UI tests that haven't needed attention).

`@preconcurrency import LemmyKit` in SpudDataKit's LemmyService and AccountService — LemmyKit declares `actor LemmyApi` but the experimental StrictConcurrency flag means consumers see it as non-Sendable across the module boundary. Drop the `@preconcurrency` once LemmyKit advances to Swift 6 language mode.

`@preconcurrency import` covers the API surface (calling actor methods) but **not** sending non-Sendable value types into actor inits. Value types crossing the boundary into a LemmyKit actor (`LemmyCredential`, etc.) need explicit `: Sendable` declared on the type itself in LemmyKit. CLI builds may pass while Xcode 16 surfaces this as an error — trust Xcode here.

`ValueObservation.start` defaults to `.async(onQueue: .main)` which is `@MainActor`-isolated and illegal from non-isolated AsyncStream init closures. All `*Observations.swift` helpers pass `.async(onQueue: .global(qos: .userInitiated))` explicitly.

## Stage 7 (Core Data demolition) — done May 2026

Core Data is gone. The migration moved persistence to GRDB and the durable account identifier to `accountKeychainId: String`. View-models and view-controllers hold the keychainId, never an account record. `AccountServiceType` is keychainId-only.

GRDB observations live in `SpudDataKit/Services/AppDatabase/*Observations.swift`; sync row-id lookups (e.g. `postRowIdSync`, `accountRowIdSync`) in the importers. Records are pure structs (Sendable when their fields are).

## Strategic direction

- **Combine → AsyncSequence / Observation** — Combine is fully retired from the Spud, SpudDataKit, and SpudUtilKit targets. View-models are `@Observable`; bind UI through the shared `ObservationStream.values(of:)` helper in `Spud/Utils/Extensions/Observation+AsyncStream.swift` (do not roll your own `withObservationTracking` loop). `@UserDefaultsBacked`'s projected value is `AsyncStream<Value>`, backed by a thread-safe `Broadcaster` class — multiple subscribers, replay-on-subscribe semantics. `PreferencesService` exposes `*Stream: AsyncStream<...>` accessors that just forward `$prop`.
- **Swift 6 language mode** — flip SpudDataKit / Spud / SpudWidget after the remaining warnings hit zero.

## Pickup checklist

What's done:

- [x] **Toolchain** — SwiftFormat 0.61.1, SwiftGen 6.6.3. `Mintfile` current.
- [x] **Format pass** — codebase reformatted under SwiftFormat 0.61.1 ruleset.
- [x] **Swift 6 — SpudUtilKit** — language mode `6.0`, builds clean.
- [x] **Swift 6 — SpudUIKit** — language mode `6.0`, builds clean. `ColorAsset` marked `@unchecked Sendable`.
- [x] **Stage 7 — Core Data demolition** — `Lemmy*` model classes, `Spud.xcdatamodeld`, `DataStore`, and every `import CoreData` are gone.
- [x] **Stage 8 — strict concurrency** — Spud / SpudDataKit / SpudWidgetExtension / OpenInAppExtension all at Swift 6.0 language mode, building clean.
- [x] **Combine — first retirement pass** — `ImageServiceType.fetchPublisher` removed; consumers (SiteListSiteViewModel, LoginViewModel) bridge AsyncStream → PassthroughSubject inline.
- [x] **Cursor-based pagination** — `LemmyService.fetchFeed(_:pageCursor:)` returns the next cursor; `PostListViewModel` tracks `nextPageCursor`. The two LemmyKit `getPosts` deprecation warnings are gone.
- [x] **Combine retirement, first half** — dead Publisher extensions (`async`, `ignoreNil`, `assignWeak`, `combineLatestSequence`, `just`/`fail`/`completed`/`empty`) deleted from SpudUtilKit. AlertService and ImageService no longer `import Combine`.
- [x] **SpudDataKitTests fakes** — rewritten for the current `Components.Schemas.*` namespace; SpudDataKitTests at Swift 6.0.
- [x] **Combine retirement, second pass** — `LoginViewModel`, `SiteListSiteViewModel`, and `PreferencesViewModel` are now `@Observable` and bind via the shared `ObservationStream.values(of:)` helper. `PreferencesService` exposes `*Stream: AsyncStream<...>` instead of `*Publisher: AnyPublisher<...>`. Dead Combine publishers in `PostListAppearance`, `PostDetailAppearance`, and `GeneralAppearance` deleted. `SpudUtilKit/Publisher+wrapInOptional` deleted.
- [x] **`@UserDefaultsBacked` Combine-free** — projected value is now `AsyncStream<Value>` backed by an internal `Broadcaster` class (NSLock-guarded continuations dictionary). Combine is no longer imported anywhere in Spud / SpudDataKit / SpudUtilKit.
- [x] **PostList lazy-feed observation fix** — `feedChanged()` now awaits the first `fetchNextPage` when the GRDB feed row hasn't been created yet, then resolves the row id and starts the observation. Without this the post list stayed empty on first launch even after the fetch returned.
- [x] **SpudTests Swift-6 flip** — `SpudTests` target at Swift 6.0 (it's stub code, no surface area). `SpudUITests` and `SpudSnapshotTests` stay at Swift 5 because they depend on third-party libraries (`SBTUITestTunnelClient`, `swift-snapshot-testing`) that haven't moved to strict concurrency yet.
- [x] **UI test triage** — the three SpudUITests cases (`testExample`, `testPostDetail`, `test_PostDetail_TapOnPostCreator`) pre-date the GRDB rewrite and the cursor-based pagination switch. They reset the filesystem and expect the feed to render straight away, but the current first-launch flow shows SiteList. Skipped via `Spud.xctestplan`'s `skippedTests` with a `FIXME` block in `SpudUITests.swift` until they're rewritten.

Build status: **Spud has 1 warning** (a benign `Duplicate -rpath '@executable_path'` from extension search-path inheritance). **Widget has 0 warnings.** **Test plan is green: 34/34 active tests pass.**

What's next:

1. **Rewrite SpudUITests** — recreate the feed-render journey against the current SiteList → signed-out-account → feed flow, refresh fixtures to the cursor pagination request shape, then unskip in `Spud.xctestplan`. Bumping the SpudUITests target to Swift 6.0 depends on `SBTUITestTunnelClient` adopting strict concurrency.

## Deferred (not blocking)

- **LemmyKit regeneration** — current API contract still working in practice. Regen when an endpoint we need has changed, or when SpudDataKit's data layer is being rewritten anyway.
- **Snapshot test refresh** — re-record on iPhone 14 Pro / portrait if/when UI changes. Reference device may want updating eventually.
- **Repo parent housekeeping** — `Spud.coredataproj` (Core Data Editor file), stray JPGs at the parent level (`3072d3c8-…` etc.). Confirm with user and remove.
- **`CHANGELOG.md` / `CONTRIBUTING.md`** — only if the project goes public.

See [README.md](README.md) for the user-facing overview.
