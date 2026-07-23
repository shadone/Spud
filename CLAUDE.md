# Spud — Claude Code working notes

Native iOS client for [Lemmy](https://join-lemmy.org) and [PieFed](https://piefed.social) (via LemmyKit's `.piefed` dialect; behavior in docs/features/piefed.md). UIKit, GRDB, SPM. Bundle ID `info.ddenis.Spud`, team `J8B76VBZ57`.

**Universal app — iPhone and iPad are both first-class.** `TARGETED_DEVICE_FAMILY` is `"1,2"`; the iPad layout is an adaptive `MainWindowSplitViewController` (sidebar + detail), not a stretched-iPhone fallback. Treat iPad as a shipping platform: new UI must work in the regular size class / split view, and any device-specific assets (e.g. the `AppIcon` set, which carries explicit iPad 152/167 sizes) must cover iPad. Snapshot tests still pin iPhone (see below), but that's a test-fixture constraint, not a statement that the app is iPhone-only.

Project went dormant after June 2024. Picked back up May 2026. The previous session was mid-migration to Swift strict concurrency (project flag `SWIFT_STRICT_CONCURRENCY = complete` is already set); that WIP lives in `git stash@{0}` (`pre-pickup-2026-05 strict-concurrency WIP`) but is intentionally being redone from scratch — do not pop it without asking.

## Quality bar (the standard every change is held to)

The goal is a genuinely great app — top-notch UI/UX that looks and feels like a native iOS citizen, on a clean codebase that's a pleasure for both humans and LLM agents to work in. Every change (feature, fix, or refactor) is held to this bar; when a shortcut would compromise it, do it properly or flag the tradeoff — don't quietly ship the lesser version.

- **Native iOS citizen.** UI/UX follows Apple's HIG and feels built-in, not ported: system controls, SF Symbols, Dynamic Type, light/dark, haptics, context menus, swipe actions, standard navigation, and smooth system-feeling animation. Adaptive across size classes — iPhone and iPad are both first-class (see the universal-app note above); exercise the regular size class / split view, not just compact.
- **Accessibility is part of "done".** VoiceOver label/trait/actions, Dynamic Type, and adequate contrast on every interactive element — designed in, not bolted on. (Snapshot tests don't catch this; cover it deliberately.)
- **Clean, legible architecture** (for humans and agents alike): respect the layer/dependency direction (`Spud → SpudDataKit / SpudUIKit / SpudMarkdownKit → SpudUtilKit`; frameworks never import the app); view-models are `@Observable`, reactive via AsyncSequence/Observation (no Combine, no Core Data); per-account flows take an `AccountScope`. Prefer many small, single-purpose files over large ones.
- **DRY + consistent.** Reuse existing components/services/helpers before adding new ones; when the same logic, copy, or label appears twice, unify it. Terminology must be consistent across screens (e.g. the action on a community is "Subscribe" everywhere — this is enforced, not incidental).
- **Documentation is paramount — three tiers, all expected on every change:**
  1. **API docs** — `///` doc comments on public/`internal` types, methods, and non-trivial properties: what it does, important parameters, and gotchas.
  2. **Internal comments** — explain the *why* of anything non-obvious (concurrency ordering, workarounds, platform quirks, deliberate tradeoffs). Never narrate the obvious.
  3. **Feature docs** — every user-facing change updates `docs/features/` at a product-manager level: shipped behavior as Given/When/Then scenarios, plus both README index sections. Keep `Status:` honest. See "Code style" → docs discipline and the `ddenis:feature-docs` skill.
- **Verify, don't assume.** Build and run the relevant unit + snapshot tests before claiming done; re-record snapshots on the reference device/runtime when UI changes; run SwiftFormat before the final verify. State outcomes faithfully.

## Project layout

`Spud.xcodeproj` is generated from `project.yml` via XcodeGen (`make project` / `xcodegen generate`); the generated project is gitignored, so `project.yml` is the source of truth. There is no longer a workspace — `LemmyKit` is consumed as a **versioned remote SPM package** (`url:` + `exactVersion:` in `project.yml`; see that file for the pinned version), resolved from its git remote. The sibling `../LemmyKit` directory is the development checkout of that package, **not** what Spud builds against — edits there don't reach Spud until they're tagged a release and the pin is bumped.

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
| `SpudTests` / `SpudDataKitTests` / `SpudUtilKitTests` / `SpudUIKitTests` | Unit tests | Per-framework. **Swift Testing** (`import Testing`, `struct` suites, `@Test`, `#expect`/`#require`) — migrated from XCTest 2026-06. |
| `SpudSnapshotTests` | Snapshot tests | Uses `pointfreeco/swift-snapshot-testing` — references recorded on **iPhone 17 Pro, portrait** (migrated from iPhone 14 Pro in 2026-06; that device has no iOS 18+ runtime) |
| `SpudUITests` | UI tests | Uses `SBTUITestTunnel` for in-app stubbing |
| `SpudMarkdownKitTests` / `SpudMarkdownKitSnapshotTests` | Unit / Snapshot tests | `SpudMarkdownKit` parser + block-render coverage. `SpudMarkdownKitTests` is Swift Testing; the snapshot target is still XCTest. |
| `MarkdownLab` | iOS app | Standalone dev harness to preview `SpudMarkdownKit` rendering in isolation |

App + extensions share keychain group `info.ddenis.Spud.shared` and app group `group.info.ddenis.Spud.shared`. The widget reads its data via `SpudDataKit` services configured against the shared container.

Dependency direction: `Spud` → `SpudDataKit` → `SpudUtilKit`; `Spud` → `SpudUIKit` → `SpudUtilKit`; `Spud` → `SpudMarkdownKit`. Frameworks must not import the app target.

## Schemes & test plans

- `Spud.xcscheme` — primary; uses `Spud.xctestplan` (all five unit-test targets — SpudTests, SpudDataKitTests, SpudUtilKitTests, SpudUIKitTests, SpudMarkdownKitTests — plus SpudUITests) and, as a second plan, `SpudSnapshots.xctestplan`
- `SpudDataKit.xcscheme` — framework dev loop
- `SpudWidgetExtension.xcscheme` — widget dev loop
- `SpudUITests.xcscheme` — UI tests in isolation
- `SpudSnapshots.xctestplan` — snapshot tests only (in the `Spud` scheme, not a separate scheme); references were recorded on the reference device **iPhone 17 Pro, portrait, iOS 26.3.x**, and the app-level images only match there (they drift across iOS minor versions). Run it with `make snapshot`, which resolves the reference device/runtime and fails fast on the wrong sim (`scripts/resolve-test-destination.sh`) — don't hand-pin a drifting `OS=` string. See [`SpudSnapshotTests/CLAUDE.md`](SpudSnapshotTests/CLAUDE.md).

## Persistence

GRDB / SQLite, in `SpudDataKit/Services/AppDatabase/`. The DB lives at
`group.info.ddenis.Spud.shared/AppDatabase/AppDatabase.sqlite` — App Group
container so the widget and extensions read the same database.

SwiftData was evaluated and rejected: it has no supported multi-process story,
and this store is opened by four processes. Settled — don't reopen it without
reading [docs/adr/0001-grdb-over-swiftdata.md](docs/adr/0001-grdb-over-swiftdata.md).

Schema migrations are GRDB `DatabaseMigrator` registrations in
`AppDatabase+Migrations.swift`. Add a new migration as the next case;
don't edit existing ones. Migrations are named `vNN_description`; the file itself is the source of truth for what exists — find the latest with `grep registerMigration AppDatabase+Migrations.swift | tail -1` and name your new one the next `vNN`. To test a **backfill** migration, use the `AppDatabase.migrator` seam (a `static var`): build a `DatabaseQueue`, `try await AppDatabase.migrator.migrate(db, upTo: "vNN")` (migrate is **async** here), insert legacy rows, `migrate(db)`, assert. `AppDatabase.inMemory()` applies ALL migrations at once, so it can't exercise an intermediate backfill.

**Durable diagnostic log.** Migration `v26_diagnosticEvent` adds a `diagnosticEvent` GRDB table that records curated lifecycle events from both outboxes, the scheduler, site-info fetches, unread refresh, offline downloads, Spotlight indexing, and app lifecycle. Events fan to both OSLog and the table via `DiagnosticLog` in `SpudDataKit/Services/Diagnostics/`. The table is pruned at launch to ≤10k rows / ≤14 days. The durable log persists across relaunches and backs the Event Log tab in About → Logs. See [docs/features/diagnostics-logging.md](docs/features/diagnostics-logging.md).

Key instrumented paths:
- `OutboxService` (mutation outbox): full drain lifecycle, including **`op.permanentRollback`** (error level) when a vote/save/hide is rolled back on a permanent server error (e.g. 403). This was previously entirely silent.
- `ComposerOutboxService` (content outbox): full drain lifecycle, including `op.permanentPark` (error level) when a content send permanently fails.
- `LemmyService.getSiteInfo`: `site.fetchFailed` (error level) now carries the **instance host** so the About → Logs viewer can answer "which site is failing" — the recurring 403 is no longer anonymous.

**Two durable outbox-style queues — don't confuse them.**
`OutboxService` / `pendingOperation` (v17): idempotent **state mutations**
(vote/save/hide), ROLLS BACK to baseline on permanent failure.
`ComposerOutboxService` / `outboundContent` (v18): **content creation** (durable
comment/post drafts + optimistic sends), PARKS a permanent failure as `failed`
(keeps the content, no rollback). Separate per-account actor + table; reuses the
outbox's `OutboxFailureClass` / `ReachabilityMonitoring` / backoff. Gotchas: don't
route create through `OutboxService` (non-idempotent → duplicates), and the
composer's `submit`/`retry` enqueue then drain in a detached `Task` (never `await`
the network send) so the optimistic UI stays instant. Composing behavior lives in
[docs/features/](docs/features/) (`replying`, `new-post`, `draft-persistence`,
`drafts-and-outbox`).

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

Post counters (`numberOfComments`, score, vote tallies) on `PostRecord` are
refreshed **only** by a full `PostView` import (`upsertPost` → `apply(view:)`):
feed `getPosts`, `getPost`, post votes, and `getPost`'s `cross_posts`. Lemmy's
`getComments` carries **no** post counters, so importing the comment tree never
updates them — the open post-detail header re-syncs the count only via the
pull-to-refresh `getPost` (`PostDetailViewController.reloadAsync` fetches post +
comments concurrently). **Trust the server's `counts`; do not derive the
comment count from the loaded comment tree** (self-healing reconciliation was
considered and rejected — see auto-memory). Incidental `PostView`s (e.g.
cross-posts) are batch-harvested via `AppDatabase.upsertPosts`.

**Mirror-then-verify when a screen OBSERVES the write.** A per-fetch `mirror*`
helper (`SpudDataKit/Services/Lemmy/`) may swallow persistence errors *only* if
nothing downstream depends on the rows. If a screen/tab renders from a GRDB
*observation* of them (not the fetch's returned response), the fetch MUST verify
the write landed (`postRowIdSync`/`personRowIdSync`/`communityRowIdSync != nil`)
and throw — else a swallowed write is a silent false-empty (feed cells, person
Posts tab) or forever-spinner with no error. Best-effort swallow is fine only for
create/moderation/subscribe paths that read the network response, not the DB.

GRDB gotcha: never `row["a"] ?? row["b"]` with two column subscripts — a
NULL *left* column wrongly collapses the whole expression to nil (a
double-optional type-inference footgun) instead of falling through to the
right column. Use `Row.coalescingString("a", "b")`. (`row["a"] ?? "literal"`
is fine; only two chained subscripts trip it.)

GRDB **`Date` storage is a mixed convention** — get it wrong and comparisons
silently break. Codable-record date columns (declared `.datetime`, e.g.
`createdAt` / `nextAttemptAt` on a `*Record`) store as ISO-8601 **text**: bind a
`Date` in SQL args (`arguments: [now]`), NOT `.timeIntervalSince1970` — a
Double-vs-text `<= ?` is silently always-false (SQLite sorts all REAL before
TEXT), so the row is never selected and no error is raised. The epoch-`.double`
date columns (`voteEvent.votedAt`, outbox `nextAttemptAt`, `diagnosticEvent.timestamp`)
are the exception — written/read via **raw SQL** as `timeIntervalSince1970`
(`Date(timeIntervalSince1970:)`). Match the column's existing convention.

To see what an importer actually stored, query the live app DB on a booted
sim: `find ~/Library/Developer/CoreSimulator/Devices -name AppDatabase.sqlite`
(app-group container, UUID path) then `sqlite3`.

**`AppDatabase` open+migrate is serialized across processes — don't break it.**
The App Group DB is opened by 4 processes (app + widget + 2 extensions) AND,
in-app, by the DI graph plus the `AppDatabase.shared` singleton. Concurrent
connections race on `PRAGMA journal_mode=WAL` and on applying the same pending
migrations (GRDB computes its unapplied set up front) → `SQLITE_BUSY` / "table
already exists" → fatal at `AppDatabase()`. `init(onDiskAt:)` holds an flock
across the whole open+migrate and `makeConfiguration` sets a busy timeout; never
open a second pool at launch or migrate from an unserialized connection. This
crashed TestFlight build 24 for everyone (Debug/sim hid it). See auto-memory
`spud-appdatabase-migration-crash`.

Core Data was demolished in Stage 7 (May 2026). `LemmyAccount` /
`LemmySite` / etc. and `DataStore` no longer exist; the durable account
identifier is `accountKeychainId: String`.

## Build & test

Prefer the `make` targets — they wrap `xcodebuild` with the required plugin/macro skip flags (`-skipPackagePluginValidation -skipMacroValidation`, needed because LemmyKit pulls in swift-openapi-generator's build-tool plugin that `xcodebuild` won't validate non-interactively) and resolve the `-destination` from `scripts/resolve-test-destination.sh`, so there's no hand-typed simulator string to drift.

```sh
# One-time
brew install mint xcodegen
make bootstrap                            # mint bootstrap + xcodegen generate
ln -sf ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit

# Regenerate the project after editing project.yml or adding/removing sources
make project                              # xcodegen generate

# Build + test (destination auto-resolved)
make build                                # build the app for the booted/reference sim
make test                                 # full Spud unit-test plan (all five unit-test targets + UI tests)
make test-only ONLY=SpudDataKitTests      # a single target from the Spud plan
make snapshot                             # snapshot plan on the reference device (iPhone 17 Pro / iOS 26.3.x)
```

`scripts/resolve-test-destination.sh` targets an already-booted sim BY ID (booting a second sim by name causes "SBMainWorkspace Busy" failures) or, when nothing is booted, the reference iPhone 17 Pro on the newest iOS 26.3.x runtime. `make snapshot` additionally FAILS if the booted sim isn't the reference device — the app-level snapshot refs only match on iPhone 17 Pro / iOS 26.3.x (see [`SpudSnapshotTests/CLAUDE.md`](SpudSnapshotTests/CLAUDE.md)). `make test` / `test-only` already pass `-test-timeouts-enabled YES -default-test-execution-time-allowance 60` so a deadlocked Swift Testing test fails-and-names instead of hanging.

Fallbacks — the faster incremental `build_and_test.py` wrapper (parses errors/warnings, supports `--json`) and raw `xcodebuild` when you need a flag the make targets don't expose. Get the `-destination` from the resolver so you never hard-code a drifting `OS=` string:

```sh
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudWidgetExtension

# Raw xcodebuild fallback
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation build

# A single snapshot class (make snapshot runs the whole plan). Newer screen snapshots
# pin a device-independent config (.image(on: .deterministicPhone)) so any sim works;
# first run records missing refs + fails, rerun verifies.
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/InstanceDetailSnapshotTests \
  -destination "$(scripts/resolve-test-destination.sh --reference)" \
  -skipPackagePluginValidation -skipMacroValidation test
```

The Xcode project is generated by XcodeGen, so `project.pbxproj` is no longer committed — the `scripts/sort-Xcode-project-file.pl` sort step the pre-commit hook used to run is no longer required (the script is kept for reference). The pre-commit hook now runs SwiftFormat in lint mode and **BLOCKS the commit on a formatting violation** (fix with `mint run swiftformat .` and re-stage).

## Release / TestFlight

Archive with `make release-project` (never `make project` — it strips the test-only tunnel that otherwise triggers ITMS-90338), then gate EVERY upload with `make verify-archive ARCHIVE=<path>` / `make verify-ipa IPA=<path>` — a non-zero exit MUST block the upload (a mis-signed archive drops the App Group entitlement, crashes the app at launch, and makes iOS wipe user data). Full runbook — `asc`-driven distribution flow, manual signing, build-number bump, and Release-crash reproduction / `.ips` symbolication — in [docs/release-runbook.md](docs/release-runbook.md).

## Code style

- `.swiftformat` is authoritative — SwiftFormat (pinned in `Mintfile`) runs via the pre-commit hook
- SwiftFormat invocation: `mint run swiftformat <paths>` (pre-commit hook runs in lint mode only — format before staging)
- `.swift-version` is the Swift toolchain pin; project-level `SWIFT_VERSION` in `pbxproj` should match
- Default branch is `main` (overrides the global "source repos use `develop`" preference)
- No emojis in code, comments, docs, or commit messages
- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`)
- Small, focused commits; split unrelated changes
- **Document every feature change in `docs/features/`** — the per-capability `<capability>.md` **and** both README index sections (the capability table **and** the "Feature coverage by area" map; they drift independently), plus any adjacent doc the change touches. Conventions and `_TEMPLATE.md` live in `docs/features/README.md`; the `ddenis:feature-docs` skill carries the full workflow and an audit script (`audit_feature_docs.py`) that checks index consistency mechanically.
- Prefer many small files over few large ones
- Inside `Task { [weak self] ... guard let self else { return } ... }`, drop the `self.` prefix on subsequent property writes — SwiftFormat's `redundantSelf` rule flags it
- `@Observable` VMs driving a `start()`/`stop()` observation loop pair `@ObservationIgnored private var …Task` with `deinit { …Task?.cancel() }` (canonical: SummaryViewModel) — copy the pattern in every new VM

## Tooling quirks

- **Swift Testing (unit tests).** All five unit-test targets are Swift Testing, not XCTest. Suites are `struct` (or `@MainActor struct`); tests are `@Test func` (no `test` prefix); `#expect`/`#require`/`Issue.record`. The **Spud** scheme's `Spud` test plan now covers all five (`SpudTests`, `SpudDataKitTests`, `SpudUtilKitTests`, `SpudUIKitTests`, `SpudMarkdownKitTests`), so run one with `make test-only ONLY=<target>`. `SpudDataKitTests` / `SpudUIKitTests` also still run via their own **SpudDataKit** / **SpudUIKit** schemes, and `SpudMarkdownKitTests` via the **SpudMarkdownKit** scheme (add `-only-testing:SpudMarkdownKitTests` to skip its snapshot sibling). The make targets already pass `-test-timeouts-enabled YES -default-test-execution-time-allowance 60` so a deadlocked test fails-and-names instead of hanging (Swift Testing waits forever for a stuck `@Test`).
- **Swift Testing runs a suite's tests in PARALLEL** (XCTest ran a class serially). Suites touching process-global mutable state (a shared `UserDefaults` suite, a `.shared` singleton, a fixed-path DB) need `@Suite(.serialized)` — see `UserDefaultsBackedTests`. `@MainActor` suites with synchronous tests are already serialized on the main actor; per-test `AppDatabase.inMemory()` is isolated.
- **Always run `mint run swiftformat` BEFORE the final test verify**, never after — formatting after a green verify can slip a rewrite into the commit that changes behavior/breaks the build. (Historical: the `--enable isEmpty` rule used to rewrite `x.count == 0` → `x.isEmpty` and break on types without `isEmpty`; it has since been removed from `.swiftformat`.)
- `import Testing` does NOT re-export Foundation (XCTest did) — files using `Date`/`URL`/`URLError`/`Data` need an explicit `import Foundation`.
- SourceKit "No such module" diagnostics in editor tooling are unreliable here — trust `build_and_test.py` over IDE squiggles.
- `project.pbxproj` is generated by XcodeGen and gitignored — never hand-edit it; change `project.yml` and run `make project`. (The old advice to monkey-patch `pbxproj`'s `remove_file_by_id` for SPM `productRef` no longer applies.)
- Run `make project` after any merge / branch-switch that adds sources or touches `project.yml` — a stale generated `.xcodeproj` yields spurious "Cannot find <symbol> in scope" for files that exist on disk but aren't in the project.
- Adding a `Has*Service` protocol to a widely-reachable VC (e.g. `InstanceDetailViewController`) **cascades** it into every VC that spells out `NestedDependencies` manually AND into the test dependency doubles (`SnapshotDependencies` in SpudSnapshotTests, `FakeDependencies`/`*Dependencies` in SpudTests) that construct those VCs (VCs composing `Dependencies` via typealias nesting auto-propagate). A missed test double surfaces as an **undefined-symbol LINKER error when the test targets build** (it references the OLD init signature) — NOT a compile error, and `make build` of the *app* alone PASSES. So build the test targets (`make test` / `make test-only ONLY=…` build the whole Spud plan) after any change to a VC's `Dependencies`, and stub each failing double (a `.unknown`-returning stub keeps snapshots byte-identical).
- The pre-commit hook's `scripts/sort-Xcode-project-file.pl` step is obsolete now that `project.pbxproj` isn't committed; the script is kept for reference.
- XCResult bundles from `build_and_test.py` live at `~/.ios-simulator-skill/xcresults/xcresult-<ts>.xcresult`. Get detailed test failure messages with `xcrun xcresulttool get test-results tests --path <bundle> --compact` — the wrapper's own `--get-errors` / `--get-warnings` only surfaces build issues, not test assertion text. To pull a failing UITest's screenshots/attachments: `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>` (the emitted `manifest.json` maps the hashed filenames back to `suggestedHumanReadableName`, e.g. your `XCTAttachment` name).
- Bumping LemmyKit: edit `exactVersion:` under `packages.LemmyKit` in `project.yml`, then `make project && xcodebuild -resolvePackageDependencies -project Spud.xcodeproj`. To force-refresh transitive SPM versions (e.g. a LemmyKit bump pulls newer openapi-* deps): `rm Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && rm -rf ~/Library/Caches/org.swift.swiftpm/repositories && xcodebuild -resolvePackageDependencies -project Spud.xcodeproj`. There is no workspace; the bare `-project` resolves the pinned remote LemmyKit directly.
- LemmyKit surfaces a non-2xx response carrying a Lemmy error body as `LemmyApiError.serverError(ErrorResponse)` (e.g. `couldnt_find_post`), NOT `.unknownServerError`. A stub `ClientTransport` returning HTTP 400 + `{"error":"..."}` reproduces it for error-path tests (see `LemmyServiceContentNotFoundTests`).
- `xcrun simctl list devices | grep Booted` — see which simulator is booted; the build wrapper auto-picks it (and its iOS version) over the configured iPhone 17 Pro unless `--simulator` is passed.
- **"Simulator device failed to launch ... Busy (Application failed preflight checks)"** is sim contention, NOT a code/snapshot failure: `-destination 'name=iPhone 17...'` boots a *second* sim while another iPhone 17 sim is already booted (e.g. running unit then snapshot tests back-to-back). Target the booted sim by **id** — `-destination 'platform=iOS Simulator,id=<UUID>'` (from `xcrun simctl list devices | grep Booted`) — and re-run.
- **A connected physical passcode-locked iPhone floods xcodebuild.** `-destination 'name=iPhone 17 Pro'` ALSO targets the device, spamming `DTDKRemoteDeviceConnection ... "device is passcode protected"` and slowing the run. Target the booted SIM by id (`-destination "platform=iOS Simulator,id=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)"`) and filter output with `grep -viE "remote service|passcode|DTDKRemote|LLVM Profile"`. (`make build`/`make test` already target the booted sim by id via `scripts/resolve-test-destination.sh`.)
- **Shell is zsh: unquoted `$var` does NOT word-split.** Building an `xcodebuild` `-only-testing:` list as a string then passing `$ARGS` fails with "Unknown build action" — use a zsh array (`args=(); args+=(-only-testing:…); xcodebuild "${args[@]}"`). Likewise quote `grep --include='*.swift'` (zsh glob-expands a bare `--include=*.swift` and errors "no matches found").
- **Swift Testing results don't appear in xcodebuild's XCTest "Executed N tests" summary** (it prints "Executed 0 tests" for a Swift-Testing-only target) — look for `✔ Test run with N tests in M suites passed` and the per-test `✔`/`✘` lines instead.
- `xcodebuild` test output spews benign environment noise: `OSStatus error:[-34018]` keychain "entitlement isn't present", `DTDKRemoteDeviceConnection ... "passcode protected"`, plus the deliberate `site.fetchFailed` / `couldnt_find_post` logs from error-path tests. None are failures — trust the `✔ Test run with N tests ... passed` line.
- The full **SpudDataKitTests** suite has one FLAKY real-network test (`NSURLErrorDomain Code=-1009` "offline" in the log): a lone `Test run ... failed ... with 1 issue` that PASSES on a clean rerun is this flake, not a regression. Isolate a genuine failure by writing the run to a file and grepping `✘ Test` / `Test run with` — inline grep truncation hides the failing-test line.
- The full **SpudTests** plan intermittently reports `CancellationError` "issues" in a few VM suites (e.g. `CommunityViewModel`/`DMThread`/`PostListViewModel`) under Swift Testing's parallelism; they PASS when run in isolation — a parallelism flake, not a regression. For a clean targeted verify, run just your changed classes: `xcodebuild … -only-testing:SpudTests/<ClassA> -only-testing:SpudTests/<ClassB> … test`.
- Don't reach for `sending` on init parameters whose type is already an actor — actors are auto-Sendable, so the `Sending '<value>' risks causing data races` diagnostic is coming from elsewhere (typically a stale Package.resolved or wrong simulator SDK).
- `build_and_test.py` on a *framework* scheme (e.g. `SpudDataKit`) defaults to the macOS ("My Mac") destination and fails the deployment-target check — pass `--simulator "iPhone 17"` (or `--platform iOS`) for iOS framework unit tests.
- `build_and_test.py --test --suite SpudDataKit` intermittently misfires with "Tests in the target 'SpudDataKit' can't be run because 'SpudDataKit' isn't a member of the specified test plan or scheme" (reports 0/0). Fall back to `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`.
- A resolve-then-show wrapper VC (`*OrLoadingViewController`, e.g. `CommunityOrLoadingViewController`) must REPLACE itself with the resolved content VC in the nav stack (`navigationController.setViewControllers(...)`), NOT host it via `add(child:)`: UIKit only renders the `navigationItem` of the controller *on* the stack, so an embedded child's navbar (overflow menu, sort button, dynamic title) silently never appears. Snapshot tests render the content VC in isolation so they DON'T catch this — cover it with a UITest that walks the real wrapper path (`test_VisitCommunityFromPostContextMenu_showsNavbarActions`). (This shipped invisible from build 8 until fixed in build 9.) Swap gotcha: if the content VC was first embedded as a child via `addSubviewWithEdgeConstraints` (which sets `translatesAutoresizingMaskIntoConstraints = false`), reset it to `true` before `setViewControllers`, or UIKit frames the new nav-root to a ZERO frame and the content area renders blank (navbar fine, body empty).
- SBTUITestTunnel stub fixtures must include EVERY required (non-`?`) field of the OpenAPI-generated response type, or decoding throws and the screen silently bails with no error UI (the importer/`*OrLoading` VC just returns). Cross-check required fields against the generated `Types.swift` (DerivedData `*LemmyKit*/…/GeneratedSources/Types.swift`). Easily-missed `GetCommunityResponse`/`Community`/`CommunityView`/`CommunityAggregates` requirements: `visibility`, `banned_from_community`, `subscribers_local` (the older `post-detail-*.json` omits `visibility` but gets away with it only because that test never asserts on the community).
- **SpudDataKit now consumes LemmyKit's version-neutral `*Neutral` API** (tri-dialect v3/v4/PieFed, v4 semantics — see LemmyKit's CLAUDE.md; the dialect is resolved from NodeInfo software, never by parsing a PieFed version string on the Lemmy scale), so UITest stubs must match the NEUTRAL wire requests, not the raw v3 endpoints. What changed and bit the stubs: community-by-name resolves via `GET /resolve_object?q=<ap_url>` (the `GET /community?name=` endpoint is RETIRED as a Spud request), and the community feed requests `community_id=` (not `community_name=`). The post-scoped `getCommentsNeutral` DOES send `max_depth=15` and no `limit` (raising `limit` alongside `max_depth` would be a lie in the request — the server ignores `limit` once `max_depth` is set); the parent-scoped ("load more replies") one sends `limit=50` (the request's page-size ceiling) and no `max_depth`. A stale stub/matcher → 500 or decode-throw → the `*OrLoading` VC silently bails and the assertion fails (reads like a UI bug, is a fixture bug). Canonical example: `resolve-object-community-tincidunt.json` + the neutral-shape refresh in `SpudUITests`/`IPadSplitUITests`.
- In an `async` test, `appDatabase.writer.write { }` resolves to GRDB's async overload — it needs `await` (synchronous tests don't).
- **Snapshot & git-annex specifics live in [`SpudSnapshotTests/CLAUDE.md`](SpudSnapshotTests/CLAUDE.md)** (auto-loaded when you work in that dir). The essentials: run the suite with `make snapshot` (resolves the reference device/runtime, fails fast on the wrong sim); references were recorded on iPhone 17 Pro / iOS 26.3.x and the full-screen app-level ones are font/runtime-sensitive; snapshot refs are git-annex-tracked (local-only — a fresh clone needs `git annex get`) while the bundled Explorer seed (`*.lzfse`) is git-lfs; re-record **one class at a time** and `git add` only the explicit refs you changed. Full ceremony (the `deterministicPhone` fix, blur on-screen rendering, async-GRDB seeding, annex restage rules, annex output noise, stale-app-on-shared-sim) is in that file.
- Stage explicit paths (never `git add -A`) — `.remember/` is a gitignored, untracked session-handoff buffer that's not yours to commit, and explicit paths keep unrelated cosmetically-modified annex snapshot refs out of your commit.
- Body markdown rendering: parse once via `MarkdownBlockCache.shared.blocks(for:)` (safe to warm off-main), then `MarkdownBodyView(context: MarkdownContext(kind: .post/.comment, textScale:, density:))`; set `.imageLoader` (a `@MainActor (URL) async -> UIImage?` wrapping `ImageService.fetch`) and `.delegate` (`MarkdownBodyDelegate`) before `setBlocks(_:)`. `MarkdownContext` bakes fonts at init, so recreate the view when the text-scale preference changes (canonical example: `PostDetailHeaderCell.makeBodyView`). `setBlocks` NO-OPS when the new blocks equal the last-applied ones (that's what makes diffable `reconfigureItems` passes flash-free) — don't add per-cell configured-blocks guards, and don't expect an equal-blocks re-set to force a rebuild or retry a failed inline image (the failed tile has its own Retry button).
- Body-text links (post & comment) render through `SpudMarkdownKit`: `InlineLexer` autolinks bare URLs and Lemmy mention shorthands (`!c@i`, `@u@i`) at parse time, and `InlineAttributedStringBuilder` stamps `.link` attributes. Bare URLs keep their real `http(s)` URL; mentions/communities become synthetic `spud-markdown://mention|community?name=…&instance=…` URLs. At **tap** time the body's `MarkdownBodyDelegate.markdownBody(didTapLink:)` fires; `MarkdownInternalLink.resolve` (`Spud/Utils/MarkdownInternalLink.swift`) translates a `spud-markdown://` link into the app's internal `URL.SpudInternalLink` (decoded by `URL.spud`), and any other URL falls through to `LemmyURLParser.classify` (path-based `/post` `/c`, bare-instance → internal link). Explicit markdown links whose destination is a Lemmy user / community / post / comment URL (`/u/name`, `/c/name`, `/post/<id>`, `/comment/<id>`, plus the frontend post form `/c/<community>/p/<id>[/<slug>]` some instances use, e.g. feddit.online) are rewritten to a synthetic `spud-markdown://` URL at render time by `InlineAttributedStringBuilder.lemmyReferenceURL` (`mention`/`community` carry name+instance; `object` carries the full URL → `.objectAtURL`), so they resolve **in-app** too (not just shorthand mentions) — bypassing `classify`'s known-instance (Explorer-directory) gate that otherwise sent unknown-instance links to Safari. (The Search field's paste-to-open uses a parallel `LemmyURLParser.frontendPostURL` for the same shape.) The old `MarkdownRenderer` / `addingAutolinks` path has been retired (the `Down` SPM dependency is gone).
- **Inline video-host playback** lives in `SpudDataKit/Services/VideoHost/` — a `VideoHost` recognize+resolve seam (streamable, PeerTube, loops.video, YouTube-via-Piped). Add a host = append it to `VideoHostRegistry`'s default hosts, which wires BOTH detector classification (`.video`) and `playVideo` playback at once; recognition is preference-free, resolution can be preference-gated (Piped reads `urlSanitizerConfig` via a Sendable snapshot passed from `playVideo`). Gotcha: SpudUtilKit's public `VideoHost` **enum** name-collides with the seam's `VideoHost` **protocol** — in any seam file that `import SpudUtilKit`, qualify the conformance as `SpudDataKit.VideoHost` (loops.video/`LoopsVideoHost` sidesteps this by not importing SpudUtilKit at all). loops.video decodes a public unsalted base-64 hashid shortcode (`/v/<code>`) to a numeric id via `LoopsHashid`, then GETs its first-party API; its default fetch sends a browser-like User-Agent because loops.video's WAF 403s non-browser UAs. See auto-memory `spud-inline-video-host-seam`.
- **Share-as-image cards are fixed designed artifacts** (`Spud/Scenes/ShareAsImage/`): inside a card view use only `ShareCardPalette` + fixed fonts — never `Theme.*`, `preferredFont`, or `UIVisualEffectView` (cards must render identically off-screen; NSFW spoiler is CIGaussianBlur), and keep `insetsLayoutMarginsFromSafeArea = false` (safe-area margin inflation was a live bug, see SpudSnapshotTests/CLAUDE.md). `ShareCardImageRenderer.render` mutates the passed view's bounds — export a FRESH card, never the editor's live preview. `nsfwRevealed` must never persist: the Codable codec strips it AND `ShareAsImageViewModel.persist()` re-strips before writing (`@UserDefaultsBacked` serves the raw in-memory value back same-session, so the codec alone doesn't cover reopen). Behavior: docs/features/share-as-image.md.
- **NodeInfo instance-software detection** lives in `SpudDataKit/Services/NodeInfo/` — `NodeInfoService` actor probes `/.well-known/nodeinfo` via the pinned `DiasporaNodeInfo` package (a 2nd remote SPM pin alongside LemmyKit), caches host→software in `NodeInfoCacheRecord` (`v30_nodeInfoCache`, TTL), and is **fail-open** (`.unknown` never blocks — a WAF-403'd Lemmy instance still logs in). `PlatformProfile`/`PlatformRouter` block a non-Lemmy login/register home connection (sheet + Open in Safari) and drive an instance-detail software badge; probe only on explicit engagement (login/register/instance-detail), never in feeds. Detection-only; `LemmyService` untouched. See [docs/features/instance-software-detection.md](docs/features/instance-software-detection.md) + auto-memory `spud-nodeinfo-keep`.
- **Fun stats (device-wide usage odometer)** lives in `SpudDataKit/Services/Stats/` (`StatsService` actor + `funStat` v39 table, NEVER pruned) with UI under `Spud/Scenes/Preferences/About/FunStats/`. Scattered one-line hooks go through the `FunStats` @MainActor static facade (`FunStats.record(.key)`, no-op when uninstalled) — a deliberate DI exception (a `Has*Service` on every hook host would cascade into all test doubles); structural consumers (DependencyContainer, SceneDelegate, the screen) still use `HasStatsService`. Hooks must fire exactly-once per USER action: at action call sites, never in outbox drains/retries; edits (post AND comment) don't count. Under XCTest the facade is never installed AND the service is force-disabled — both guards required because SceneDelegate's lifecycle calls bypass the facade. Behavior: [docs/features/fun-stats.md](docs/features/fun-stats.md).
- Reproducing a Release-only / first-launch crash on the sim and symbolicating a TestFlight `.ips` are in [docs/release-runbook.md](docs/release-runbook.md).
- **idb tap automation is DEAD here** (idb crashes under Homebrew Python 3.14: `asyncio.get_event_loop()` no-event-loop), so the `ios-simulator-skill`'s navigator / screen_mapper / tap don't work, and `xcrun simctl openurl` with the `info.ddenis.spud://` scheme raises an untappable "Open in Spud?" SpringBoard prompt. Drive on-device UI with **XCUITest** (in-process taps work) — see auto-memory `spud_ui_test_sim_flake`.
- **`SBTStubResponse(fileNamed:)` NSAsserts at registration if the fixture file is missing** → the whole UITest class crashes in `setUp` and reports "Executed 0 tests" (reads like it never ran, not like a failure — this silently disabled the iPad split test). Every fixture JSON referenced in a UITest's stubs must exist in the UITest target.
- **Three test-only UITest launch arguments** (`AppLaunchArgument.swift`; the signed-in seed and the wipe are `#if DEBUG`-compiled, the signed-out seed is runtime-guarded only): `SPUDSeedSignedOutDefaultAccount` and `SPUDSeedSignedInDefaultAccount` seed a default account synchronously before the account-presence gate (signed-in also inserts a person row + a fake JWT under a fixed keychainId, so repeated runs overwrite instead of accumulating keychain entries); `SPUDWipeAppDatabase` deletes the whole App Group `AppDatabase` directory before `AppDatabase.shared` first opens it. The wipe exists because the App Group DB **survives SBT's `ResetFilesystem`** (and `simctl uninstall`) — a signed-out account left by an earlier suite makes a later signed-in seed no-op. Signed-in UITests must pass **both** args (wipe + seed) to be order-independent on a shared sim. The legacy signed-out suites (`SpudUITests`, `IPadSplitUITests`) now pass the wipe arg too, so seeds are order-independent in both directions — a signed-in account left by an alphabetically-earlier suite can no longer make their signed-out seed a no-op.
- **iOS 26 AutoFill breaks XCUITest secure-field typing**: once any credential was ever saved on the sim, `typeText` into a password field silently drops (empty field, "Passwords" AutoFill bar over the keyboard). `SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete` and `simctl keychain reset` do NOT help. For live-login automation, prefill the field via an env-var seam (`TEST_RUNNER_`-forwarded ProcessInfo variable) instead of typing. This is why `NodeInfoBlockUITests` can be red for purely environmental reasons (owed a prefill-seam rework) — not a product bug.
- **iPad-only UITests need an iOS 26.x iPad simulator** — `iPad Pro 11-inch (M5)`. The `iPad Pro 11-inch (M4)` sim on the iOS 18.5 runtime is a DUD for this app: that runtime lacks `libswiftWebKit.dylib` (which `SpudDataKit` links for the v25 WKWebView offline-archive feature), so the app dyld-crashes at every launch — it reads as an instant test failure/hang, not a code bug. Respect the single-booted-sim rule around these runs: shut down the iPhone first, boot the iPad by id, then shut the iPad down and reboot the reference iPhone afterward.
- **`SpudTests` shares `UserDefaults.standard` with the real app.** It's hosted inside the `Spud` app target (`project.yml`'s `dependencies: - target: Spud`), so a bare `PreferencesService()` there reads/writes the exact `info.ddenis.Spud` defaults domain a later `SpudUITests` launch reads from — and SBT's `ResetFilesystem` does not reliably clear it. Build test preferences via `PreferencesService.ephemeral()` (SpudTests, `SpudTests/EphemeralPreferences.swift`) or `SnapshotPreferences.ephemeral()` (SpudSnapshotTests, `SpudSnapshotTests/SnapshotDeterminism.swift`) — each call gets its own private `UserDefaults` suite, so tests stay isolated from `.standard` and from each other with no restore dance needed. The old workaround (`defer`-restoring every mutated key to its documented default, plus `@Suite(.serialized)` to stop Swift Testing's default parallelism from racing the shared keys) is retired for ordinary tests; keep it only for a suite that deliberately exercises `.standard` itself, e.g. `PreferencesServiceStorageIsolationTests`.
- **Search rows must reconcile per-account state (subscribe/save/vote) against the persisted GRDB record — the `LemmyService.search` / `listCommunities` responses are TRANSIENT and never mirrored to the DB.** Community subscribe-state truth is `CommunityRecord.subscribedState` (5-valued `CommunitySubscribedState`: `.notSubscribed`/`.subscribed`/`.pending`/`.approvalRequired`/`.denied`), observed live via `AppDatabase.observeFollowedCommunities(forAccountId:)`; resolve with **persisted-wins** over the network `followState`. Rendering subscribe-state from a lossy `Bool` (`followState == .accepted`) was the bug that showed "Subscribed" for a `.pending` (approval-gated) community and reverted to "Subscribe" on re-search (fixed 2026-07-14).
- **Long-press context menus live in `Spud/Utils/ContextMenus/`** — per-entity `@MainActor` host protocols + near-pure builders returning `UIMenu` (Post/Community/Comment/User/Instance). The POST menu is the shared `PostContextMenuBuilder` extracted from `PostListViewController`'s feed menu (the feed consumes it, so its menu can't drift from Search's); reuse the builder+host pattern for any new entity long-press menu, and attach via `contextMenuConfigurationForRowAt`. Menus can't be snapshot-tested (cells render in isolation) — unit-test the builder's `UIMenu` tree + a nav UITest. Subscribe-button copy (Subscribe/Subscribed/Pending/Requested) is centralized in `Spud/Utils/CommunitySubscribeButtonLabel.swift` — don't re-hardcode it.
- A button inside an `isUserInteractionEnabled = false` superview renders normally but can never receive a finger tap (hit-testing doesn't descend into disabled views) — and BOTH `sendActions(for:)` in unit tests and VoiceOver activation bypass hit-testing, so neither catches it. Tests for tap affordances must assert `hitTest` reachability at the button's center (see `ImageBlockViewTests.failedPlateButtonsAreHitTestReachable`; this shipped the inline-image "Open in browser" button dead from its introduction).
- **Review/verify subagents in this shared checkout must be given an explicit read-only git constraint** (plain `git show`/`diff`/`log`, Read, Grep only — no `git stash`, `git reset`, `git checkout --`, no deleting files). A reviewer once ran `git stash`+`pop` to check a diff and popped the protected `stash@{0}` WIP into a conflicted tree; after any subagent git mishap, verify `git stash list`/`log`/`status -u` firsthand before trusting its report.
- **A subagent that backgrounds a long `make test`/`make snapshot` (the full plan is ~5+ min incl. SpudUITests) then ends its turn pauses with NO terminal status** — poll the process (`pgrep -f "xcodebuild.*-scheme Spud"`) and resume the subagent once it exits to verify+commit. Don't infer green from the process merely having ended. A subagent resumed to finalize often re-runs the suite and re-pauses (a finalize LOOP) — after one such cycle, verify the diff + run just the changed test classes yourself and commit directly instead of resuming again. When you DO take over: a subagent's turn-end notification is NOT termination — an earlier SendMessage can leave it re-animating later, and two actors then race the same worktree (observed: snapshot refs re-recorded/reverted under each other). Take over only after it reports a terminal status, or send an explicit stand-down first.

## Strict concurrency

`SWIFT_STRICT_CONCURRENCY = complete` is on at the project level. Every shipped target — Spud, SpudDataKit, SpudWidgetExtension, OpenInAppExtension, SpudUtilKit, SpudUIKit — **and all five unit-test targets** (SpudTests, SpudDataKitTests, SpudUtilKitTests, SpudUIKitTests, SpudMarkdownKitTests) inherit Swift 6.0 language mode + complete strict concurrency from the project base (no per-target override). Only `SpudUITests` and the two snapshot targets (`SpudSnapshotTests`, `SpudMarkdownKitSnapshotTests`) are pinned to 5.0 — they depend on third-party libs (`SBTUITestTunnelClient`, `swift-snapshot-testing`) not yet on strict concurrency.

LemmyKit is at Swift 6 language mode (since 0.3.0) with Sendable on its hand-written types and openapi-generator >= 1.5 emits Sendable on every generated response type, so `import LemmyKit` (no `@preconcurrency`) works in SpudDataKit. Required: LemmyKit checkout has the openapi-generator dep bump (>= 1.12) **and** the build targets iOS 18+ SDK — iOS 17 SDK still flags `Sending 'self.api'` at every cross-actor `await api.xxx(...)` site.

The bare `Spud.xcodeproj` is the only build target — it resolves LemmyKit from its pinned remote release (the `exactVersion:` in `project.yml`), which transitively brings openapi-generator 1.12.x, satisfying the >= 1.12 requirement above. The old workspace-vs-project gotcha (11 `Sending 'self.api' risks causing data races` errors in `LemmyService.swift` from a stale pinned resolve of older openapi versions) no longer applies: there is no workspace, and a release pin can't drift mid-session the way the live sibling checkout could.

`ValueObservation.start` defaults to `.async(onQueue: .main)` which is `@MainActor`-isolated and illegal from non-isolated AsyncStream init closures. All `*Observations.swift` helpers pass `.async(onQueue: .global(qos: .userInitiated))` explicitly.

A `static let` non-Sendable formatter (`ISO8601DateFormatter`/`DateFormatter`) in a non-`@MainActor` type fails Swift 6 ("not concurrency-safe"). SwiftUI `View` structs are `@MainActor` so their static formatters compile; a plain enum/struct helper is not — build the formatter locally per call (the codebase convention) or use a Sendable `FormatStyle`.

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

## Accounts / instances

Login / register / anonymous browse are all keyed on a bare `InstanceActorId`
carried in a `SiteListRow` — directory (Explorer) metadata (name/icon/stats) is
decorative, and `AccountService.ensureSite(forInstance:)` stands up an account
from a bare host with no `getSite`. Build a row for an arbitrary/typed host with
`SiteListRow.forTypedInstance(_:)` (also used by the custom-instance entry flow +
the `MainWindow` DEBUG seam). The NodeInfo non-Lemmy block
(`AccountService.preflightHomeConnection` → `PlatformRouter`) runs before both
login and register and is **fail-open** (unknown/unreachable → allow), so it never
false-blocks a private/WAF'd Lemmy instance — it only blocks confirmed non-Lemmy.

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
- **Snapshot test refresh** — re-record on iPhone 17 Pro / portrait if/when UI changes (the reference device was migrated from iPhone 14 Pro to iPhone 17 Pro in 2026-06, when the whole suite was refreshed).
- **`CHANGELOG.md` / `CONTRIBUTING.md`** — only if the project goes public.

See [README.md](README.md) for the user-facing overview.
