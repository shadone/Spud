# Stage 7 demolition — resume plan

Snapshot taken 2026-05-04. `main` carries the in-flight migration off Core Data + Combine onto GRDB + AsyncStream/@Observable. Both `Spud` and `SpudWidgetExtension` build clean.

## Where we are

Stage 7 = "Demolition" of Core Data inside SpudDataKit. Sub-commits already on `main`:

```
44e5604 refactor: drive MainWindow off GRDB observeDefaultAccount
37d71d8 refactor: dispatch SchedulerService through keychainId
fcf0632 refactor: drop LemmyAccount from AccountList and Login
c381230 refactor: drop LemmyAccount from PreferencesViewModel
46fddbb refactor: hold accountKeychainId in PostList/PostDetail/Person/Subs
8d0537c refactor: add keychainId-keyed AccountService overloads
11cb364 refactor: migrate PostDetail flow off LemmyPost/LemmyPostInfo
d9d638e refactor: migrate Person flow off LemmyPerson/LemmyPersonInfo
e9b5689 refactor: move feed lifecycle from LemmyFeed to FeedHandle
fe5e20e refactor: switch LemmyService API from NSManagedObjectID to server ids
2c20fc3 refactor: cut widget over to GRDB
```

The Spud app target has zero `LemmyAccount` references. View-controllers and view-models hold `accountKeychainId: String` and dispatch through `AccountServiceType.{lemmyService,lemmyDataService,createFeed,setDefaultAccount}(forAccountKeychainId:)` overloads.

`grep -rln LemmyAccount Spud --include='*.swift'` should return nothing.

## What's still in 3c

Each item is a small, contained change; not blocking on each other. None are required before starting 3d, but they shrink the LemmyAccount surface inside SpudDataKit.

1. **`LoginViewController.continueWithSignedOutAccount`** — calls `accountForSignedOut(at: LemmySite, ...) -> LemmyAccount` then `setDefaultAccount(_:)`. Replace with a single `AccountServiceType.signInAsSignedOut(at: LemmySite)` that does both internally; the LemmySite stays (boundary moves in 3d).
2. **`AppCoordinator.open(_:in:)`** — does `siteService.site(for:in:)` → `accountService.account(at:in:)` → extract `.id`. Add `accountKeychainId(forInstance: InstanceActorId) -> String?` to `AccountServiceType` (or push the lookup into `AppDatabase`) so this call site doesn't touch `LemmyAccount`.
3. **`SchedulerService` predicates** — still uses `allSignedOut(in:)` / `allAccounts(includeSignedOutAccount:in:)` and filters by `account.site.siteInfo == nil` / `account.accountInfo == nil` / `now - account.updatedAt > 1 day`. Replace each with a GRDB-backed query over `AccountRecord` + `SiteRecord`.

## Stage 3d — final demolition

This is the multi-session piece. Rough order; each step keeps the build green. Stages 1–7 are done as of 2026-05-04; 8 is a continuous chore performed alongside each delete commit.

1. ~~**Rewrite `LemmyService` end-to-end on GRDB.**~~ Done.
2. ~~**Rewrite `LemmyDataService` or remove it.**~~ Removed.
3. ~~**Rewrite `SchedulerService` on GRDB.**~~ Done.
4. ~~**Drop legacy `AccountServiceType` API.**~~ Done. Surface is keychainId-only plus `accountForSignedOut(forInstance:)`.
5. ~~**Delete the `*+import.swift` dual-write helpers**~~ Done.
6. ~~**Delete the `Lemmy*` model classes**~~ Done. All 21 NSManagedObject subclasses gone.
7. ~~**Delete `Spud.xcdatamodeld`, `DataStore`, `HasDataStore`** and `import CoreData`.~~ Done. `import Combine` deferred to Stage 8 because AlertService / ImageService still expose Combine pipelines.
8. ~~**Run `pbxproj` cleanup**~~ Audited — zero dangling/unreferenced ids.

## Stage 8 — Swift 6 strict concurrency on data + app layers

Project flag `SWIFT_STRICT_CONCURRENCY = complete` is already on. Pickup order:

1. SpudDataKit (now GRDB-only): explicit `Sendable` annotations on records, actor-isolated services. No `@unchecked Sendable` unless invariant is documented.
2. Spud app target: walk the warnings; expect most to come from the few remaining `@MainActor` boundaries that are currently lax.
3. SpudWidgetExtension + OpenInAppExtension.

LemmyKit already enables `StrictConcurrency` and `DisableOutwardActorInference` — no work there.

## Hard rules (carried forward from autonomous brief)

- Stay on `main`. NO push to origin. NO force-push.
- NO `--no-verify` on commits — pre-commit hook (sort-Xcode-project-file.pl + SwiftFormat lint) must pass.
- Run `mint run swiftformat <paths>` before staging.
- Build BOTH `Spud` and `SpudWidgetExtension` schemes via `build_and_test.py` after every commit.
- Don't delete files outside the migration scope. Don't pop `git stash@{0}` (`pre-pickup-2026-05 strict-concurrency WIP`) without asking.

## Quick orientation when resuming

```sh
# Verify clean checkpoint
git status                                  # should be clean
git log --oneline -12                       # confirm above sub-commits
grep -rln LemmyAccount Spud --include='*.swift'   # should be empty

# Build both targets
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/ios-simulator-skill/scripts/build_and_test.py --scheme Spud
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/ios-simulator-skill/scripts/build_and_test.py --scheme SpudWidgetExtension
```

Files of interest:

- `SpudDataKit/Services/Account/AccountService.swift` — parallel keychainId/LemmyAccount API surface lives here.
- `SpudDataKit/Services/AppDatabase/Observations.swift` — `observeDefaultAccount`, `observeAccounts`, post/comment/person observations.
- `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift` — `accountRowIdSync`, `accountInstanceActorIdSync`, `setDefaultAccount(keychainId:)`.
- `SpudDataKit/Services/AppDatabase/Records/Account.swift` — `AccountRecord` + `resolvedDefaultSortType`.
- `SpudDataKit/Services/Lemmy/LemmyService.swift` — the big 3d rewrite target.
- `SpudDataKit/Services/Scheduler/SchedulerService.swift` — internal Core Data fetches still here.
