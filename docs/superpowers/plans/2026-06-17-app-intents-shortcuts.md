# App Intents + App Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose Spud to Siri, Spotlight, the Action button, and Shortcuts via a real set of App Intents (Open Feed, Search, New Post, Open Inbox, Open Community), an `AppShortcutsProvider`, and a Spotlight-indexed `CommunityAppEntity`.

**Architecture:** Intents (`openAppWhenRun = true`) call a typed navigation router on `AppCoordinator` (`navigate(_:)`), which either drives the live `MainWindow` (via an `AppNavigating` protocol, for testability) or stores a one-slot `pendingNavigation` that `SceneDelegate` drains on launch. The `CommunityAppEntity` query reads the shared App-Group GRDB the same way the widget does.

**Tech Stack:** Swift 6 / UIKit / GRDB / AppIntents / CoreSpotlight (`IndexedEntity`). Build/test via `build_and_test.py`.

## Global Constraints

- iOS deployment target **18.0**; Swift **6.0**, `SWIFT_STRICT_CONCURRENCY = complete`.
- New intent/entity/provider files live in the **Spud app target** under `Spud/Intents/` (auto-included via the target's `- Spud` source — no `project.yml` change; verify with `make project` after adding files). They must NOT go in `Shared/Intents` (compiled into the widget too).
- Reuse the existing `IntentFeedTypeAppEnum` / `IntentSortTypeAppEnum` (`Shared/Intents/TopPostsAppIntent/`) and their `Components.Schemas.ListingType`/`SortType` converters.
- All intents operate on the current default account (`AccountService.currentDefaultAccountKeychainId()`), like the widget. Signed-out reuses the in-app sign-in gate.
- Build/test: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"` (add `--test --suite SpudTests`/`SpudDataKit` for unit tests). Keep the widget building: `--scheme SpudWidgetExtension`.
- SwiftFormat before staging (`mint run swiftformat <paths>`). No emojis. Conventional commits. Stage explicit paths (git-annex snapshot noise; never `git add -A`).

---

## Slice A — Navigation router (backbone, unit-testable)

### Task A1: `AppNavigation` + `AppNavigating` + `AppCoordinator.navigate`

**Files:**
- Create: `Spud/App/AppNavigation.swift`
- Modify: `Spud/App/AppCoordinator.swift`
- Test: `SpudTests/AppNavigationRoutingTests.swift`

**Interfaces:**
- Produces:
  - `enum AppNavigation: Equatable { case feed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?); case search(query: String); case newPost; case inbox; case community(name: String, instance: InstanceActorId) }`
  - `protocol AppNavigating: AnyObject { func selectFeed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?); func selectSearch(query: String); func presentNewPost(); func selectInbox(); func display(communityName: String, instance: InstanceActorId, accountKeychainId: String) }`
  - On `AppCoordinator`: `weak var activeWindow: AppNavigating?`, `private(set) var pendingNavigation: AppNavigation?`, `func setActiveWindow(_:)`, `func navigate(_:)`, `func drainPendingNavigation()`, and `var dependencies: DependencyContainer` (exists).

- [ ] **Step 1: Write `Spud/App/AppNavigation.swift`** with the enum and protocol above (import `LemmyKit`, `SpudUtilKit`).

- [ ] **Step 2: Write the failing test** `SpudTests/AppNavigationRoutingTests.swift`:

```swift
import LemmyKit
import SpudUtilKit
import XCTest
@testable import Spud

final class AppNavigationRoutingTests: XCTestCase {
    final class SpyNavigator: AppNavigating {
        var calls: [String] = []
        func selectFeed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?) { calls.append("feed:\(listing.rawValue):\(sort?.rawValue ?? "nil")") }
        func selectSearch(query: String) { calls.append("search:\(query)") }
        func presentNewPost() { calls.append("newPost") }
        func selectInbox() { calls.append("inbox") }
        func display(communityName: String, instance: InstanceActorId, accountKeychainId: String) { calls.append("community:\(communityName)") }
    }

    @MainActor
    func test_navigate_withActiveWindow_routesImmediately() {
        let coordinator = AppCoordinator.shared
        let spy = SpyNavigator()
        coordinator.setActiveWindow(spy)
        coordinator.navigate(.inbox)
        coordinator.navigate(.search(query: "cats"))
        XCTAssertEqual(spy.calls, ["inbox", "search:cats"])
        XCTAssertNil(coordinator.pendingNavigation)
    }

    @MainActor
    func test_navigate_withNoWindow_storesPending_thenDrains() {
        let coordinator = AppCoordinator.shared
        coordinator.setActiveWindow(nil)
        coordinator.navigate(.newPost)
        XCTAssertEqual(coordinator.pendingNavigation, .newPost)
        let spy = SpyNavigator()
        coordinator.setActiveWindow(spy)
        coordinator.drainPendingNavigation()
        XCTAssertEqual(spy.calls, ["newPost"])
        XCTAssertNil(coordinator.pendingNavigation)
    }
}
```

  (Note: `AppCoordinator.shared` is a singleton; `setActiveWindow(nil)` resets state between tests. If shared-singleton coupling makes the test flaky, extract the routing into a `NavigationRouter` value type that `AppCoordinator` owns and test that instead — preferred if clean.)

- [ ] **Step 3: Run test, verify it fails** (`navigate`/`setActiveWindow` undefined).

Run: `python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`

- [ ] **Step 4: Implement** on `AppCoordinator`:

```swift
weak var activeWindow: AppNavigating?
private(set) var pendingNavigation: AppNavigation?

func setActiveWindow(_ window: AppNavigating?) {
    activeWindow = window
}

func navigate(_ target: AppNavigation) {
    guard let window = activeWindow else {
        pendingNavigation = target
        return
    }
    apply(target, to: window)
}

func drainPendingNavigation() {
    guard let target = pendingNavigation, let window = activeWindow else { return }
    pendingNavigation = nil
    apply(target, to: window)
}

private func apply(_ target: AppNavigation, to window: AppNavigating) {
    switch target {
    case let .feed(listing, sort): window.selectFeed(listing: listing, sort: sort)
    case let .search(query): window.selectSearch(query: query)
    case .newPost: window.presentNewPost()
    case .inbox: window.selectInbox()
    case let .community(name, instance):
        let keychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
        window.display(communityName: name, instance: instance, accountKeychainId: keychainId)
    }
}
```

- [ ] **Step 5: Run tests, verify pass. Commit.**

```bash
mint run swiftformat Spud/App/AppNavigation.swift Spud/App/AppCoordinator.swift SpudTests/AppNavigationRoutingTests.swift
git add Spud/App/AppNavigation.swift Spud/App/AppCoordinator.swift SpudTests/AppNavigationRoutingTests.swift
git commit -m "feat: typed navigation router on AppCoordinator with deferred replay"
```

### Task A2: `MainWindow` conforms to `AppNavigating`

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (expose a feed-apply entry)

**Interfaces:**
- Consumes: `splitViewController.postListNavigationController`, `PostListViewModel.switchFeed(to:)`, `tabBarController`, `composeTapped` path, existing `display(communityName:instance:accountKeychainId:)`.
- Produces: `MainWindow: AppNavigating`; `PostListViewController.showFeed(_ feedType: FeedType)`.

- [ ] **Step 1: Add `showFeed` to `PostListViewController`** (it already has a private `switchFeed(to:)` at line 365 that calls `viewModel.switchFeed` + `feedChanged()`):

```swift
/// Switches the post list to a different feed (used by deep navigation / intents).
func showFeed(_ feedType: FeedType) {
    switchFeed(to: feedType)
}
```

- [ ] **Step 2: Implement `AppNavigating` on `MainWindow`** (tab order is Posts 0 | Communities 1 | Search 2 | Inbox 3 | Account 4). For the feed sort default, use the account's default post sort preference if available, else `.Hot`:

```swift
extension MainWindow: AppNavigating {
    func selectFeed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?) {
        tabBarController.selectedIndex = 0
        let sortType = sort ?? .Hot
        let postListVC = splitViewController?.postListNavigationController
            .viewControllers.first as? PostListViewController
        postListVC?.showFeed(.frontpage(listingType: listing, sortType: sortType))
    }

    func selectSearch(query: String) {
        tabBarController.selectedIndex = 2
        guard
            let nav = tabBarController.viewControllers?[2] as? UINavigationController,
            let searchVC = nav.viewControllers.first as? SearchViewController
        else { return }
        searchVC.setSearchQuery(query)
    }

    func presentNewPost() {
        // Reuse the compose entry on the Posts tab (handles the sign-in gate).
        tabBarController.selectedIndex = 0
        let postListVC = splitViewController?.postListNavigationController
            .viewControllers.first as? PostListViewController
        postListVC?.beginNewPost()
    }

    func selectInbox() {
        tabBarController.selectedIndex = 3
    }
    // display(communityName:instance:accountKeychainId:) already exists.
}
```

  Add the small public entries this needs:
  - `SearchViewController.setSearchQuery(_ query: String)` — sets `searchController.searchBar.text = query`, makes the search controller active, and calls `viewModel.queryChanged(query)`.
  - `PostListViewController.beginNewPost()` — calls the existing private `composeTapped()`.

  (Verify the exact existing private method names — `composeTapped()` at line 375 — and the `splitViewController` accessibility from `MainWindow`. If `splitViewController` is private, route through an existing internal accessor or add one.)

- [ ] **Step 3: Build, verify it compiles.**

Run: `python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17"`

- [ ] **Step 4: Format + commit.**

```bash
mint run swiftformat Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/Search/SearchViewController.swift
git add Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/Search/SearchViewController.swift
git commit -m "feat: MainWindow conforms to AppNavigating (feed/search/newPost/inbox)"
```

### Task A3: Register the active window in `SceneDelegate`

**Files:**
- Modify: `Spud/App/SceneDelegate.swift`

- [ ] **Step 1: Register + drain.** In `scene(_:willConnectTo:)` after the window is built, add `AppCoordinator.shared.setActiveWindow(window)` and `AppCoordinator.shared.drainPendingNavigation()`. In `sceneDidBecomeActive`, add `AppCoordinator.shared.setActiveWindow(window); AppCoordinator.shared.drainPendingNavigation()`. In `sceneDidDisconnect`, `AppCoordinator.shared.setActiveWindow(nil)`.

- [ ] **Step 2: Build, verify. Commit.**

```bash
git add Spud/App/SceneDelegate.swift
git commit -m "feat: register active window for intent navigation"
```

---

## Slice B — Simple intents + AppShortcutsProvider

### Task B1: The four parameter-light intents

**Files:**
- Create: `Spud/Intents/OpenFeedAppIntent.swift`, `Spud/Intents/SearchLemmyAppIntent.swift`, `Spud/Intents/NewPostAppIntent.swift`, `Spud/Intents/OpenInboxAppIntent.swift`

**Interfaces:**
- Consumes: `AppCoordinator.shared.navigate(_:)`, `IntentFeedTypeAppEnum`, `IntentSortTypeAppEnum`, the `Components.Schemas.ListingType.init(from:)` converter (exists), and a `SortType.init(from: IntentSortTypeAppEnum)` converter (exists in `Shared/Intents/TopPostsAppIntent/SortType+appintent.swift` — verify; if missing, add it).

- [ ] **Step 1: Implement the intents.** Example `OpenFeedAppIntent`:

```swift
import AppIntents

struct OpenFeedAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Feed"
    static let openAppWhenRun = true

    @Parameter(title: "Category", default: .subscribed)
    var feedType: IntentFeedTypeAppEnum

    @Parameter(title: "Sort")
    var sortType: IntentSortTypeAppEnum?

    @MainActor
    func perform() async throws -> some IntentResult {
        let listing = Components.Schemas.ListingType(from: feedType)
        let sort = sortType.map { Components.Schemas.SortType(from: $0) }
        AppCoordinator.shared.navigate(.feed(listing: listing, sort: sort))
        return .result()
    }
}
```

  `SearchLemmyAppIntent` (`@Parameter(title: "Query") var query: String` → `.navigate(.search(query: query))`), `NewPostAppIntent` (no params → `.navigate(.newPost)`), `OpenInboxAppIntent` (no params → `.navigate(.inbox)`). All set `openAppWhenRun = true`, `@MainActor func perform()`.

- [ ] **Step 2: Build** (`--scheme Spud`). Intents have no direct unit test (they're thin wrappers over the router covered in A1); compile is the gate.

- [ ] **Step 3: Commit.**

```bash
git add Spud/Intents/OpenFeedAppIntent.swift Spud/Intents/SearchLemmyAppIntent.swift Spud/Intents/NewPostAppIntent.swift Spud/Intents/OpenInboxAppIntent.swift
git commit -m "feat: Open Feed / Search / New Post / Open Inbox app intents"
```

### Task B2: `SpudAppShortcuts` provider

**Files:**
- Create: `Spud/Intents/SpudAppShortcuts.swift`

- [ ] **Step 1: Implement** the `AppShortcutsProvider` (see spec for phrase list; every phrase must contain `\(.applicationName)`). Include the four B1 intents now; the community shortcut is added in Task C3.

- [ ] **Step 2: Build, then verify discovery manually** — run the app on the sim, open the Shortcuts app, confirm the four actions appear under Spud, and "Hey Siri, new post in Spud" launches the composer.

- [ ] **Step 3: Commit.**

```bash
git add Spud/Intents/SpudAppShortcuts.swift
git commit -m "feat: AppShortcutsProvider with Siri phrases"
```

---

## Slice C — Community entity

### Task C1: One-shot followed-communities query

**Files:**
- Create or modify: `SpudDataKit/Services/AppDatabase/CommunityQueries.swift` (new) — add a sync read
- Test: `SpudDataKitTests/FollowedCommunitiesQueryTests.swift`

**Interfaces:**
- Produces: `extension AppDatabase { func followedCommunitiesSync(forAccountId accountId: Int64) -> [CommunityRecord] }` mirroring the SQL in `Observations.swift:141`.

- [ ] **Step 1: Write the failing test** — seed an in-memory `AppDatabase` (`try AppDatabase.inMemory()`) with an account, two communities, and `accountFollowedCommunity` rows, then assert `followedCommunitiesSync(forAccountId:)` returns both ordered by lowercased name. (Reuse existing test helpers that insert `CommunityRecord` / account / follow rows — search `SpudDataKitTests` for an existing subscription/follow seeding helper; if none, insert via `appDatabase.write` with the records.)

- [ ] **Step 2: Run, verify fail. Step 3: Implement** the sync read:

```swift
func followedCommunitiesSync(forAccountId accountId: Int64) -> [CommunityRecord] {
    (try? reader.read { db in
        try CommunityRecord.fetchAll(db, sql: """
            SELECT community.*
            FROM community
            JOIN accountFollowedCommunity AS afc ON afc.communityId = community.id
            WHERE afc.accountId = ?
            ORDER BY LOWER(community.name) ASC
        """, arguments: [accountId])
    }) ?? []
}
```

  (Verify the `reader`/`writer` accessor name used by other sync queries in `ExplorerQueries.swift` — it uses `writer.read`; match it.)

- [ ] **Step 4: Run tests, verify pass. Commit.**

```bash
git add SpudDataKit/Services/AppDatabase/CommunityQueries.swift SpudDataKitTests/FollowedCommunitiesQueryTests.swift
git commit -m "feat: followedCommunitiesSync query"
```

### Task C2: `CommunityAppEntity` + `CommunityEntityQuery`

**Files:**
- Create: `Spud/Intents/CommunityAppEntity.swift`, `Spud/Intents/CommunityEntityQuery.swift`
- Test: `SpudTests/CommunityEntityQueryTests.swift`

**Interfaces:**
- Consumes: `AppDatabase()` (shared App-Group open), `AccountService(appDatabase:)`, `accountRowIdSync(forKeychainId:)`, `followedCommunitiesSync(forAccountId:)`, `CommunityRecord` fields (verify: `name`, the community actor id → `InstanceActorId`, icon `URL?`).
- Produces: `CommunityAppEntity` (`AppEntity`, `IndexedEntity`) with `id: String` (`"name@host"`), `name`, `instance: InstanceActorId`, `iconURL: URL?`; `CommunityEntityQuery: EntityStringQuery`.

- [ ] **Step 1: Investigate field names.** Open `CommunityRecord` (find: `find SpudDataKit -name 'CommunityRecord.swift'`) and confirm the name, actor-id/instance, and icon accessors. Build a `CommunityAppEntity(from: CommunityRecord)` mapper.

- [ ] **Step 2: Write the failing test** — seed an in-memory DB + default account + two followed communities; build a query that injects that `AppDatabase`/`AccountService` (add a test init `CommunityEntityQuery(reader:)` or a protocol seam so the test doesn't hit the real App-Group DB). Assert `suggestedEntities()` returns both, `entities(matching: "tech")` filters by name, `entities(for: [id])` round-trips.

- [ ] **Step 3: Implement** `CommunityAppEntity` and the query. The query resolves the default account, its row id, and the followed communities; `entities(matching:)` filters `suggestedEntities()` by case-insensitive name contains. For production it opens the shared DB (`try AppDatabase()`); the test seam injects an in-memory one. `displayRepresentation` uses name + host + icon. Defer the `IndexedEntity` `attributeSet` to Task D1 (a minimal conformance compiles now).

- [ ] **Step 4: Run tests, verify pass. Build `--scheme Spud`. Commit.**

```bash
git add Spud/Intents/CommunityAppEntity.swift Spud/Intents/CommunityEntityQuery.swift SpudTests/CommunityEntityQueryTests.swift
git commit -m "feat: CommunityAppEntity backed by subscriptions"
```

### Task C3: `OpenCommunityAppIntent` + shortcut

**Files:**
- Create: `Spud/Intents/OpenCommunityAppIntent.swift`
- Modify: `Spud/Intents/SpudAppShortcuts.swift`

- [ ] **Step 1: Implement** the intent (`@Parameter var community: CommunityAppEntity`; `perform()` → `AppCoordinator.shared.navigate(.community(name: community.name, instance: community.instance))`; donate via `IntentDonationManager.shared.donate(intent:)`). Add an `AppShortcut(intent: OpenCommunityAppIntent(), phrases: ["Open \(\.$community) in \(.applicationName)"], ...)` to the provider.

- [ ] **Step 2: Build, manual-verify** — Shortcuts app shows "Open Community" with a community picker populated from subscriptions; running it opens the community.

- [ ] **Step 3: Commit.**

```bash
git add Spud/Intents/OpenCommunityAppIntent.swift Spud/Intents/SpudAppShortcuts.swift
git commit -m "feat: Open Community app intent + shortcut"
```

---

## Slice D — Spotlight indexing

### Task D1: Index subscribed communities into Spotlight

**Files:**
- Create: `Spud/Intents/CommunitySpotlightIndexer.swift`
- Modify: `Spud/Intents/CommunityAppEntity.swift` (flesh out `IndexedEntity.attributeSet`), a launch hook (e.g. `AppCoordinator` startup), and the subscribe/unsubscribe path.

- [ ] **Step 1: Investigate the API** on the pinned SDK: `import CoreSpotlight`; confirm `CSSearchableIndex.default().indexAppEntities(_:)` (iOS 18) signature and the `IndexedEntity.attributeSet` property (a `CSSearchableItemAttributeSet` — set `title` = name, `contentDescription` = host).
- [ ] **Step 2: Implement** `CommunitySpotlightIndexer.indexSubscribedCommunities()` that loads the default account's followed communities, maps to `CommunityAppEntity`, and calls `CSSearchableIndex.default().indexAppEntities(_:)`. Call it once on app start (after the default account resolves) and on subscribe/unsubscribe (hook the existing subscription write or a GRDB observation of follows).
- [ ] **Step 3: Build, manual-verify** — after running the app with subscriptions, search a community name in system Spotlight; tapping the result opens it (routes via `OpenCommunityAppIntent`).
- [ ] **Step 4: Commit.**

```bash
git add Spud/Intents/CommunitySpotlightIndexer.swift Spud/Intents/CommunityAppEntity.swift Spud/App/AppCoordinator.swift
git commit -m "feat: index subscribed communities into Spotlight"
```

---

## Slice E — Retire the legacy donation

### Task E1: Remove the app's SiriKit donation

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`

- [ ] **Step 1: Delete** `donateIntent()` (and its three call sites at ~lines 374/405/694) and the now-unused `import Intents`. Do NOT touch the widget's `ViewTopPostsIntent`/`.intentdefinition` usage.
- [ ] **Step 2: Build both schemes** — `--scheme Spud` and `--scheme SpudWidgetExtension` — to confirm nothing else referenced `donateIntent`/`INInteraction` and the widget still builds.
- [ ] **Step 3: Commit.**

```bash
git add Spud/Scenes/PostList/PostListViewController.swift
git commit -m "refactor: remove legacy SiriKit intent donation from PostList"
```

---

## Slice F — Docs

### Task F1: Feature doc

**Files:**
- Create: `docs/features/app-shortcuts-and-siri.md` (follow the `_TEMPLATE.md` format: Surfaces, Status, Related, What it does, Behavior and rules, Scenarios, Not supported / out of scope).

- [ ] Document the five intents, the Siri phrases, the community entity + Spotlight, account/sign-out behavior, and out-of-scope items. Cross-link from `docs/features/widget.md` (shared intent enums) and `docs/features/README.md`. Commit `docs: app shortcuts and Siri feature doc`.

---

## Self-Review notes

- **Spec coverage:** router (A1–A3) ✓; five intents (B1, C3) ✓; AppShortcutsProvider (B2, C3) ✓; CommunityAppEntity + query (C1, C2) ✓; IndexedEntity/Spotlight (D1) ✓; legacy cleanup (E1) ✓; default-account/sign-out reuse (A2 presentNewPost, B/C intents) ✓; docs (F1) ✓.
- **Investigate-then-implement (not placeholders):** `CommunityRecord` field names (C2.1), `IndexedEntity`/`indexAppEntities` API (D1.1), `SortType.init(from:)` existence (B1), `splitViewController`/private-method accessibility on MainWindow/PostList (A2). Each has a grounded fallback.
- **Type consistency:** `AppNavigation`/`AppNavigating` method names (`selectFeed(listing:sort:)`, `selectSearch(query:)`, `presentNewPost()`, `selectInbox()`, `display(communityName:instance:accountKeychainId:)`) are identical in A1 (definition/test), A2 (conformance), and the `apply(_:to:)` dispatch. `CommunityAppEntity` properties (`id`,`name`,`instance`,`iconURL`) consistent across C2/C3/D1.
