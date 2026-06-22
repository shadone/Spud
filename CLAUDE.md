# Spud — Claude Code working notes

Native iOS client for [Lemmy](https://join-lemmy.org). UIKit, GRDB, SPM. Bundle ID `info.ddenis.Spud`, team `J8B76VBZ57`.

Project went dormant after June 2024. Picked back up May 2026. The previous session was mid-migration to Swift strict concurrency (project flag `SWIFT_STRICT_CONCURRENCY = complete` is already set); that WIP lives in `git stash@{0}` (`pre-pickup-2026-05 strict-concurrency WIP`) but is intentionally being redone from scratch — do not pop it without asking.

## Project layout

`Spud.xcodeproj` is generated from `project.yml` via XcodeGen (`make project` / `xcodegen generate`); the generated project is gitignored, so `project.yml` is the source of truth. There is no longer a workspace — `LemmyKit` is consumed as a **versioned remote SPM package** (`url:` + `exactVersion:` in `project.yml`, currently pinned to 0.5.0), resolved from its git remote. The sibling `../LemmyKit` directory is the development checkout of that package, **not** what Spud builds against — edits there don't reach Spud until they're tagged a release and the pin is bumped.

```
info.ddenis/Spud/
├── Spud/                       ← this repo (the iOS app)
│   ├── project.yml             ← XcodeGen spec (source of truth)
│   └── Spud.xcodeproj          ← generated, gitignored
└── LemmyKit/                   ← dev checkout of the LemmyKit package (Spud builds the tagged release, not this)
```

Open the generated `Spud.xcodeproj` (run `make project` first on a fresh checkout). Spud resolves LemmyKit from its git remote at the pinned tag, so a fresh build needs no sibling checkout. See the workspace-level `../CLAUDE.md` for the inventory of every directory at this level (live, reference-only, historical).

## Targets

| Target | Type | Purpose |
|---|---|---|
| `Spud` | iOS app | Main app — UIKit scenes, coordinators, view models |
| `SpudWidgetExtension` | App extension | Home-screen widget showing top posts |
| `OpenInAppExtension` | App extension | "Open in Spud" share/action extension |
| `SpudDataKit` | Framework | Domain layer — GRDB store, Lemmy services, scheduler, image service |
| `SpudUIKit` | Framework | Design tokens, color/symbol resources, SwiftGen-generated assets |
| `SpudUtilKit` | Framework | Foundation extensions, `UserDefaultsBacked`, `Atomic`, `Logger`, etc. |
| `SpudMarkdownKit` | Framework | Markdown parsing + rendering: `MarkdownParser` → `[MarkdownBlock]` → `MarkdownBodyView`. No app/data deps (uses `apple/swift-markdown`) |
| `SpudTests` / `SpudDataKitTests` / `SpudUtilKitTests` | Unit tests | Per-framework |
| `SpudSnapshotTests` | Snapshot tests | Uses `pointfreeco/swift-snapshot-testing` — locked to **iPhone 14 Pro, portrait** |
| `SpudUITests` | UI tests | Uses `SBTUITestTunnel` for in-app stubbing |
| `SpudMarkdownKitTests` / `SpudMarkdownKitSnapshotTests` | Unit / Snapshot tests | `SpudMarkdownKit` parser + block-render coverage |
| `MarkdownLab` | iOS app | Standalone dev harness to preview `SpudMarkdownKit` rendering in isolation |

App + extensions share keychain group `info.ddenis.Spud.shared` and app group `group.info.ddenis.Spud.shared`. The widget reads its data via `SpudDataKit` services configured against the shared container.

Dependency direction: `Spud` → `SpudDataKit` → `SpudUtilKit`; `Spud` → `SpudUIKit` → `SpudUtilKit`; `Spud` → `SpudMarkdownKit`. Frameworks must not import the app target.

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

`post.isSaved` lives on `PostRecord` (the `post` table), **not** on
`postInteraction` (the local interaction log: `titleSnapshot`,
`lastOpenedAt`/`lastSeenAt`, new-comment delta, FTS `postInteractionFts`).
Saved / History / Spotlight reads join `postInteraction -> post -> community`
(canonical: `observeHistoryRows`); the canonical post `ap_id` is
`post.originalPostUrl`.

GRDB gotcha: never `row["a"] ?? row["b"]` with two column subscripts — a
NULL *left* column wrongly collapses the whole expression to nil (a
double-optional type-inference footgun) instead of falling through to the
right column. Use `Row.coalescingString("a", "b")`. (`row["a"] ?? "literal"`
is fine; only two chained subscripts trip it.)

To see what an importer actually stored, query the live app DB on a booted
sim: `find ~/Library/Developer/CoreSimulator/Devices -name AppDatabase.sqlite`
(app-group container, UUID path) then `sqlite3`.

Core Data was demolished in Stage 7 (May 2026). `LemmyAccount` /
`LemmySite` / etc. and `DataStore` no longer exist; the durable account
identifier is `accountKeychainId: String`.

## Build & test

```sh
# One-time
brew install mint xcodegen
make bootstrap                            # mint bootstrap + xcodegen generate
ln -sf ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit

# Regenerate the project after editing project.yml or adding/removing sources
make project                              # xcodegen generate

# Build (bare project — no workspace). The agentic build_and_test.py wrapper expects
# --simulator "iPhone 17 Pro" — match that here unless you know a 15 Pro is installed.
# Fresh derived-data builds need the plugin/macro skip flags (LemmyKit pulls in
# swift-openapi-generator's build-tool plugin, which xcodebuild won't validate
# non-interactively): add -skipPackagePluginValidation -skipMacroValidation.
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Unit tests
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Snapshot tests — iPhone 14 Pro is required
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test

# Run a single snapshot class (the build_and_test.py wrapper has no --testPlan, so use
# xcodebuild). Newer screen snapshots pin a config (.image(on: .iPhone13Pro, traits:)) so
# they're device-independent — any sim works; first run records missing refs + fails, rerun verifies.
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/InstanceDetailSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test

# Faster build path used in agentic sessions — incremental, parses errors/warnings,
# supports --json. Fall back to xcodebuild only if you need flags it doesn't expose.
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudWidgetExtension
```

The Xcode project is generated by XcodeGen, so `project.pbxproj` is no longer committed — the `scripts/sort-Xcode-project-file.pl` sort step the pre-commit hook used to run is no longer required (the script is kept for reference).

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
- `project.pbxproj` is generated by XcodeGen and gitignored — never hand-edit it; change `project.yml` and run `make project`. (The old advice to monkey-patch `pbxproj`'s `remove_file_by_id` for SPM `productRef` no longer applies.)
- Run `make project` after any merge / branch-switch that adds sources or touches `project.yml` — a stale generated `.xcodeproj` yields spurious "Cannot find <symbol> in scope" for files that exist on disk but aren't in the project.
- The pre-commit hook's `scripts/sort-Xcode-project-file.pl` step is obsolete now that `project.pbxproj` isn't committed; the script is kept for reference.
- XCResult bundles from `build_and_test.py` live at `~/.ios-simulator-skill/xcresults/xcresult-<ts>.xcresult`. Get detailed test failure messages with `xcrun xcresulttool get test-results tests --path <bundle> --compact` — the wrapper's own `--get-errors` / `--get-warnings` only surfaces build issues, not test assertion text.
- Bumping LemmyKit: edit `exactVersion:` under `packages.LemmyKit` in `project.yml`, then `make project && xcodebuild -resolvePackageDependencies -project Spud.xcodeproj`. To force-refresh transitive SPM versions (e.g. a LemmyKit bump pulls newer openapi-* deps): `rm Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && rm -rf ~/Library/Caches/org.swift.swiftpm/repositories && xcodebuild -resolvePackageDependencies -project Spud.xcodeproj`. There is no workspace; the bare `-project` resolves the pinned remote LemmyKit directly.
- `xcrun simctl list devices | grep Booted` — see which simulator is booted; the build wrapper auto-picks it (and its iOS version) over the configured iPhone 17 Pro unless `--simulator` is passed.
- Don't reach for `sending` on init parameters whose type is already an actor — actors are auto-Sendable, so the `Sending '<value>' risks causing data races` diagnostic is coming from elsewhere (typically a stale Package.resolved or wrong simulator SDK).
- `build_and_test.py` on a *framework* scheme (e.g. `SpudDataKit`) defaults to the macOS ("My Mac") destination and fails the deployment-target check — pass `--simulator "iPhone 17"` (or `--platform iOS`) for iOS framework unit tests.
- `build_and_test.py --test --suite SpudDataKit` intermittently misfires with "Tests in the target 'SpudDataKit' can't be run because 'SpudDataKit' isn't a member of the specified test plan or scheme" (reports 0/0). Fall back to `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`.
- Snapshot a view controller by passing a fake struct conforming to its `Dependencies` composition (e.g. `StaticImageService()` + `AlertService()` + `AccountService(appDatabase: try AppDatabase.inMemory())`); fixtures with nil image URLs render placeholders deterministically (no async image loading).
- Snapshotting a scrollable screen with `.image(on: .iPhone13Pro)` captures only the device viewport — pass a `size:` (full content height) so below-the-fold sections are in frame.
- In an `async` test, `appDatabase.writer.write { }` resolves to GRDB's async overload — it needs `await` (synchronous tests don't).
- Large binaries: **git-lfs** tracks `SpudDataKit/Resources/*.lzfse` (bundled Explorer seed); **git-annex** (unlocked, scoped via `.gitattributes` to all of `SpudSnapshotTests/__Snapshots__/**`) tracks every snapshot reference. Annex content is **local-only** (origin has no git-annex) — a fresh clone needs `git annex get`; sharing needs an annex special remote.
- Re-recording snapshot refs (git-annex): record/verify **one snapshot class at a time** and never `git annex restage` between the record and verify runs — restage reverts the just-written PNGs (verify then reports "No reference"); after a green verify, `git add` (the annex clean filter stores them). The "content availability has changed … unable to update the index" status is cosmetic (`git add`/`commit` work) but makes refs read as persistently "modified", which blocks `git merge`/`git checkout` ("local changes would be overwritten") — commit the new refs first so the tree is clean. Count written PNGs with `find`, not `ls …/*.png` (zsh aborts on no-match).
- `git status` here is configured `showUntrackedFiles=no` — plain `git status` / `--short` shows only *modified* files and silently hides untracked ones. Use `git status -uall` to see new files before committing, or you'll miss newly-added sources/tests/snapshots. Stage explicit paths (never `git add -A`): `.remember/remember.md` is a session-handoff buffer that's almost always dirty and is not yours to commit.
- Body markdown rendering: parse once via `MarkdownBlockCache.shared.blocks(for:)` (safe to warm off-main), then `MarkdownBodyView(context: MarkdownContext(kind: .post/.comment, textScale:, density:))`; set `.imageLoader` (a `@MainActor (URL) async -> UIImage?` wrapping `ImageService.fetch`) and `.delegate` (`MarkdownBodyDelegate`) before `setBlocks(_:)`. `MarkdownContext` bakes fonts at init, so recreate the view when the text-scale preference changes (canonical example: `PostDetailHeaderCell.makeBodyView`).
- Body-text links (post & comment) render through `SpudMarkdownKit`: `InlineLexer` autolinks bare URLs and Lemmy mention shorthands (`!c@i`, `@u@i`) at parse time, and `InlineAttributedStringBuilder` stamps `.link` attributes. Bare URLs keep their real `http(s)` URL; mentions/communities become synthetic `spud-markdown://mention|community?name=…&instance=…` URLs. At **tap** time the body's `MarkdownBodyDelegate.markdownBody(didTapLink:)` fires; `MarkdownInternalLink.resolve` (`Spud/Utils/MarkdownInternalLink.swift`) translates a `spud-markdown://` link into the app's internal `URL.SpudInternalLink` (decoded by `URL.spud`), and any other URL falls through to `LemmyURLParser.classify` (path-based `/post` `/c`, bare-instance → internal link). The old `MarkdownRenderer` / `addingAutolinks` path has been retired (the `Down` SPM dependency is gone).

## Strict concurrency

`SWIFT_STRICT_CONCURRENCY = complete` is on at the project level. Every shipped target — Spud, SpudDataKit, SpudWidgetExtension, OpenInAppExtension, SpudUtilKit, SpudUIKit — and SpudDataKitTests are at Swift 6.0 language mode. SpudTests, SpudUITests, and SpudSnapshotTests remain at 5.0 (they're stubs / UI tests that haven't needed attention).

LemmyKit is at Swift 6 language mode (since 0.3.0) with Sendable on its hand-written types and openapi-generator >= 1.5 emits Sendable on every generated response type, so `import LemmyKit` (no `@preconcurrency`) works in SpudDataKit. Required: LemmyKit checkout has the openapi-generator dep bump (>= 1.12) **and** the build targets iOS 18+ SDK — iOS 17 SDK still flags `Sending 'self.api'` at every cross-actor `await api.xxx(...)` site.

The bare `Spud.xcodeproj` is the only build target — it resolves LemmyKit from its pinned remote release (`exactVersion: 0.5.0`), which transitively brings openapi-generator 1.12.x, satisfying the >= 1.12 requirement above. The old workspace-vs-project gotcha (11 `Sending 'self.api' risks causing data races` errors in `LemmyService.swift` from a stale pinned resolve of older openapi versions) no longer applies: there is no workspace, and a release pin can't drift mid-session the way the live sibling checkout could.

`ValueObservation.start` defaults to `.async(onQueue: .main)` which is `@MainActor`-isolated and illegal from non-isolated AsyncStream init closures. All `*Observations.swift` helpers pass `.async(onQueue: .global(qos: .userInitiated))` explicitly.

## Stage 7 (Core Data demolition) — done May 2026

Core Data is gone. The migration moved persistence to GRDB and the durable account identifier to `accountKeychainId: String`. View-models and view-controllers hold the keychainId, never an account record. `AccountServiceType` is keychainId-only.

GRDB observations live in `SpudDataKit/Services/AppDatabase/*Observations.swift`; sync row-id lookups (e.g. `postRowIdSync`, `accountRowIdSync`) in the importers. Records are pure structs (Sendable when their fields are).

Per-account dependency scope: a single-account screen takes an `AccountScope`
(`accountService.scope(forAccountKeychainId:)`), not a bare keychain id, and reads
its per-account connection through it — `scope.lemmyService`, `scope.isSignedOut`,
`scope.instanceActorId`. `AccountScope` is a zero-cost **lazy facade** over
`AccountServiceType` (accessors resolve live, so a long-lived scope never serves a
stale snapshot). Only the per-account connection/identity lives on the scope;
account *management* (`createFeed`, `defaultSortType`, login/logout) and the
account-*selection* layer (`MainWindow`, account-list / preferences) call
`AccountServiceType` directly.

## Strategic direction

- **Combine → AsyncSequence / Observation** — Combine is fully retired from the Spud, SpudDataKit, and SpudUtilKit targets. View-models are `@Observable`; bind UI through the shared `ObservationStream.values(of:)` helper in `Spud/Utils/Extensions/Observation+AsyncStream.swift` (do not roll your own `withObservationTracking` loop). `@UserDefaultsBacked`'s projected value is `AsyncStream<Value>`, backed by a thread-safe `Broadcaster` class — multiple subscribers, replay-on-subscribe semantics. `PreferencesService` exposes `*Stream: AsyncStream<...>` accessors that just forward `$prop`.
- **Swift 6 language mode** — flip SpudDataKit / Spud / SpudWidget after the remaining warnings hit zero.

## System integration (deep links, App Intents, Handoff, Spotlight)

- Every system entry point — deep links, App Intents, `NSUserActivity` / Handoff continuation, Spotlight item taps — funnels into `AppCoordinator.open(_:in:)` (URL targets) or `.navigate(AppNavigation)` (typed targets) via the `info.ddenis.spud://internal/...` routing URL. Build that URL with the **nested** `URL.SpudInternalLink` (`.objectAtURL(ap_id)` for posts/people, `.community(name, instance)` for communities) — it is `URL.SpudInternalLink`, not a top-level `SpudInternalLink`. `SceneDelegate.scene(_:continue:)` decodes both our activity types and `CSSearchableItemActionType` (Spotlight taps).
- Background contexts (App Intents entity queries, Spotlight indexers) read GRDB **off-main** via nonisolated `AppDatabase` `*Sync` helpers — `AccountService` is `@MainActor` and unusable there. App Intents entity queries inject a `@Sendable () -> [Entity]` closure (production reads the shared `AppDatabase()`; tests inject) — see `CommunityEntityQuery` / `AccountEntityQuery`.
- Placement: App Intents + entities in `Spud/Intents/`; `NSUserActivity` + Spotlight helpers in `Spud/Integration/`. **App-target only — never put this in `Shared/`** (it would compile into the widget). New files need `make project` (XcodeGen).
- Spotlight has two indexers, both fire-and-forget reindex on launch (`MainWindow.applyDefaultAccount`) + foreground (`SceneDelegate.sceneWillEnterForeground`): `CommunitySpotlightIndexer` (subscriptions, `indexAppEntities`) and `ContentSpotlightIndexer` (saved + history, domain `"content"`, `indexSearchableItems`).

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
- [x] **SpudUITests rewrite** — `testExample` and `testPostDetail` are unskipped and green. Fixtures were patched for current required schema fields (`banned_from_community`, `creator_is_moderator`, `creator_is_admin`, community `visibility`, `hidden`); SBT query matchers had to drop the leading `&` (they're regex-matched against the request query string and the first param has no leading `&`); the post detail's "attribution" is now a `LinkLabel` whose accessibility type computes inconsistently between legacy and modern attributes — query via `descendants(matching: .any)["attribution"]`, not `buttons[]` or `staticTexts[]`. The bootstrap path on first launch creates a signed-out account on `discuss.tchncs.de` automatically; no SiteList navigation is needed in the test. `test_PostDetail_TapOnPostCreator` is now active and green: it queries the creator's link directly (`detailHeaderCell.links["<creator name>"]`), asserts the element carries its destination URL as its accessibility value, and taps it — no coordinate-offset hack, because `LinkLabel` now exposes per-link accessibility children (see the done item below).

- [x] **LinkLabel per-link accessibility** (shipped in `aed9d96`) — each link range in an attributed `LinkLabel` is now its own `UIAccessibilityElement` child (label = link text, value = destination URL, `.link` trait), so VoiceOver can land on and activate individual links and XCUITest can tap them by name. This re-enabled `test_PostDetail_TapOnPostCreator`.

Build status: **Spud has 1 warning** (a benign `Duplicate -rpath '@executable_path'` from extension search-path inheritance). **Widget has 0 warnings.** **Test plan is green**, with `test_PostDetail_TapOnPostCreator` now in the active set (no longer a `skip_` stub).

What's next:

- No outstanding items from the strict-concurrency / accessibility pickup. For current shipped behavior, the per-capability docs under [docs/features/](docs/features/README.md) are authoritative.

## Deferred (not blocking)

- **LemmyKit regeneration** — current API contract still working in practice. Regen when an endpoint we need has changed, or when SpudDataKit's data layer is being rewritten anyway.
- **Snapshot test refresh** — re-record on iPhone 14 Pro / portrait if/when UI changes. Reference device may want updating eventually.
- **`CHANGELOG.md` / `CONTRIBUTING.md`** — only if the project goes public.

See [README.md](README.md) for the user-facing overview.
