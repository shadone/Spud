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
- No emojis in code, comments, docs, or commit messages
- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`)
- Small, focused commits; split unrelated changes
- Prefer many small files over few large ones

## Tooling quirks

- SourceKit "No such module" diagnostics in editor tooling are unreliable here — trust `build_and_test.py` over IDE squiggles.
- Editing `Spud.xcodeproj/project.pbxproj` from Python: `pbxproj`'s `remove_file_by_id` assumes every `PBXBuildFile` has `fileRef`, but SPM product refs use `productRef`. Monkey-patch with a `getattr(build_file, 'fileRef', None) or getattr(build_file, 'productRef', None)` fallback before calling.
- Pre-commit hook runs `scripts/sort-Xcode-project-file.pl` automatically; never bypass with `--no-verify`.

## Strict concurrency

`SWIFT_STRICT_CONCURRENCY = complete` is already on at the project level. The earlier WIP attempted to silence the resulting warnings ad-hoc (saw commits like "Added a hack to silence strict concurrency warning", "Quick fix for strict concurrency warnings"). The fresh approach should be Swift 6 language mode end-to-end: explicit `Sendable` annotations, actor-isolated services, no `@unchecked` escape hatches unless the invariant is documented. LemmyKit already enables `StrictConcurrency` and `DisableOutwardActorInference`.

## Strategic direction (decided May 2026)

Two stack changes are committed to before continuing the Swift 6 migration on the data/app layers:

- **Replace Core Data** — the model in `SpudDataKit/Services/DataStore/` is being replaced (SwiftData is the obvious candidate but the choice isn't locked; discuss before assuming). Driven by Apple's de-emphasis of Core Data and friction with Widgets in particular.
- **Replace Combine** — `AnyPublisher` / `CurrentValueSubject` / `.sink` pipelines throughout `SpudDataKit` are being replaced with `AsyncSequence` and Observation. Same reasoning.

Treat the old `LemmyService` / `DataStore` design as transitional — do not invest in actor-isolation refactors there.

### Stage 7 conventions (in-flight migration off LemmyAccount)

- `LemmyAccount.id` is the keychain id (String). Treat it as the durable account identifier — view-models and view-controllers in the Spud target hold `accountKeychainId: String`, never `LemmyAccount`.
- `AccountServiceType` carries two parallel APIs during the migration: `for: LemmyAccount` and `forAccountKeychainId: String`. App-target code uses the keychainId variants; the LemmyAccount variants are SpudDataKit-internal and disappear in 3d.
- GRDB observations live in `SpudDataKit/Services/AppDatabase/*Observations.swift`; sync row-id lookups (e.g. `postRowIdSync`, `accountRowIdSync`) in the importers.

## Pickup checklist

What's done:

- [x] **Toolchain** — SwiftFormat 0.61.1, SwiftGen 6.6.3. `Mintfile` current.
- [x] **Format pass** — codebase reformatted under SwiftFormat 0.61.1 ruleset.
- [x] **Swift 6 — SpudUtilKit** — language mode `6.0`, builds clean.
- [x] **Swift 6 — SpudUIKit** — language mode `6.0`, builds clean. `ColorAsset` marked `@unchecked Sendable` next to its existing extension (not in the SwiftGen-generated file).

What's next, in order:

1. **Decide replacement for Core Data.** SwiftData is the default candidate but evaluate against the Widget integration story and the existing entity graph (Instance, LemmyAccount, LemmyCommunity, LemmyPerson, LemmyPost, LemmyComment, LemmyFeed, LemmyPage, plus *Info companions). Old `Spud.xcdatamodel` only has one version — no migration history to preserve.
2. **Decide replacement for Combine.** Likely `AsyncSequence` for streams, `@Observable` for view-model state, plain `async`/`await` for one-shot calls. Note `AnyPublisher.async()` extension in SpudUtilKit can be retired entirely once nothing emits Combine.
3. **Plan migration sequence.** Persistence first or reactive layer first? `LemmyService` heavily mixes both, so they likely move together.
4. **Then resume Swift 6 migration** on the rewritten `SpudDataKit`, the app target, the widget, and `OpenInAppExtension`. Don't migrate LemmyService's current actor isolation now — it's getting replaced.

## Deferred (not blocking)

- **Deployment target bump** — mixed `15.0` / `15.2` / `16.0`; user confirmed app builds + runs fine on current devices, so not urgent. Bump when there's a concrete iOS-version-gated API to adopt.
- **SPM `Package.resolved`** — last refreshed mid-2024; not blocking.
- **LemmyKit regeneration** — current API contract still working in practice. Regen when an endpoint we need has changed, or when SpudDataKit's data layer is being rewritten anyway.
- **`SpudDataKitTests` compile errors** — pre-existing, references `Comment`, `CommentAggregates`, `CommentView`, `Community`, `Person`, `Post` types that LemmyKit's OpenAPI generator now namespaces under `Components.Schemas.*`. Likely auto-fixed by the data-layer rewrite; don't sink time into patching the fakes.
- **Snapshot test refresh** — re-record on iPhone 14 Pro / portrait if/when UI changes. Reference device may want updating eventually.
- **Repo parent housekeeping** — `Spud.coredataproj` (Core Data Editor file), stray JPGs at the parent level (`3072d3c8-…` etc.). Confirm with user and remove.
- **`CHANGELOG.md` / `CONTRIBUTING.md`** — only if the project goes public.

See [README.md](README.md) for the user-facing overview.
