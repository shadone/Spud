# Handoff / Spotlight / App Intents Completion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close Spud's three remaining "deep iOS integration" gaps — NSUserActivity/Handoff, App Intents completion (Open Saved, Switch Account, per-community donation), and proactive Spotlight indexing of saved + viewed content — all routed through one `info.ddenis.spud://internal/…` URL into `AppCoordinator`.

**Architecture:** Every system surface (deep links [done], App Intents, NSUserActivity continuation, Spotlight item taps) decodes to a canonical routing URL and funnels into `AppCoordinator.open(_:in:)` (URL targets) or `AppCoordinator.navigate(_:)` (typed `AppNavigation` targets). New app-target-only code lives under `Spud/Intents/` (intents + entities) and a new `Spud/Integration/` group (activity factory, Spotlight indexer). Off-main GRDB reads go in `SpudDataKit` as nonisolated sync helpers.

**Tech Stack:** Swift 6 (strict concurrency `complete`), UIKit, GRDB, App Intents, CoreSpotlight, XcodeGen.

## Global Constraints

- **Strict concurrency:** Spud + SpudDataKit are Swift 6 language mode. `AccountService` is `@MainActor`; background entity/Spotlight code must read the shared GRDB **off-main** via nonisolated `AppDatabase` sync helpers (precedent: `followedCommunitiesForDefaultAccountSync`). `AppDatabase` is `final class … : Sendable`.
- **Placement:** intents/entities → `Spud/Intents/`; activity + Spotlight helpers → `Spud/Integration/` (new group). **App-target only — never put this code in any `Shared/` dir** (it would compile into the widget too). Data-layer reads → `SpudDataKit/Services/AppDatabase/`.
- **XcodeGen:** new files/dirs require `make project` (run from `Spud/`) before they build. `project.pbxproj` is generated/gitignored — never hand-edit; `Spud/` source paths glob subdirs, so `Spud/Integration/` is auto-included after regen.
- **Routing URL vocabulary:** build every routing URL via `SpudInternalLink` (`SpudUtilKit/Extensions/URL+spud.swift`): `.objectAtURL(url:)` for posts/people (canonical `ap_id`), `.community(name:instance:)` for communities. `.url` encodes; `URL.spud` decodes; `AppCoordinator.open` dispatches.
- **Build/test wrapper:** `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`. Add `--test --suite SpudTests` (app-target unit tests) or `--test --suite SpudDataKit` (data-layer tests). An iPhone 17 sim is booted; the wrapper auto-picks it.
- **Pre-commit:** `mint run swiftformat <changed paths>` before every commit (the pre-commit hook lints). No emojis anywhere. Conventional commit subjects (`feat:`/`fix:`/`test:`). Small focused commits.
- **Git hygiene:** `git status -uall` to see untracked files (`status.showUntrackedFiles=no` hides them). **Stage explicit paths — never `git add -A`.** git-annex marks `__Snapshots__/**` PNGs as cosmetically modified; ignore them. `.remember/remember.md` is a session buffer — never commit it.

---

## File Structure

**New files:**
- `Spud/Integration/SpudUserActivity.swift` — NSUserActivity factory + decoder (pure).
- `Spud/Integration/ContentSpotlightIndexer.swift` — saved/history → `CSSearchableItem`.
- `Spud/Intents/OpenSavedAppIntent.swift` — Open Saved feed intent.
- `Spud/Intents/AccountAppEntity.swift` — account `AppEntity`.
- `Spud/Intents/AccountEntityQuery.swift` — account entity query (test-injectable).
- `Spud/Intents/SwitchAccountAppIntent.swift` — switch default account intent.
- `SpudDataKit/Services/AppDatabase/PersonQueries.swift` — `personActorIdSync`.
- `SpudDataKit/Services/AppDatabase/AccountQueries.swift` — `accountsSync`.
- `SpudDataKit/Services/AppDatabase/SpotlightContentQueries.swift` — `IndexableContentRow` + indexable-rows reads.
- `SpudTests/SpudUserActivityTests.swift`, `SpudTests/AccountEntityQueryTests.swift`, `SpudTests/ContentSpotlightIndexerTests.swift`.
- `SpudDataKitTests/PersonQueriesTests.swift`, `SpudDataKitTests/AccountQueriesTests.swift`, `SpudDataKitTests/SpotlightContentQueriesTests.swift`.

**Modified files:**
- `Spud/App/AppNavigation.swift` — add `.savedFeed` case + `selectSavedFeed` protocol method.
- `Spud/App/AppCoordinator.swift` — handle `.savedFeed` in `apply`.
- `Spud/Scenes/MainWindow/MainWindow.swift` — implement `selectSavedFeed`; hook `ContentSpotlightIndexer.reindex`.
- `Spud/App/SceneDelegate.swift` — `scene(_:continue:)` + cold-launch userActivity handling + content reindex on foreground.
- `Spud/Resources/Info.plist` — replace stale `NSUserActivityTypes`.
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, `Spud/Scenes/Community/Content/CommunityViewController.swift`, `Spud/Scenes/Person/Content/PersonViewController.swift` — vend activities.
- `Spud/Intents/OpenCommunityAppIntent.swift` — add donation.
- `Spud/Intents/SpudAppShortcuts.swift` — add Open Saved + Switch Account.
- `SpudTests/AppNavigationRoutingTests.swift` — `.savedFeed` spy + test.

---

# Slice 1 — NSUserActivity / Handoff

### Task 1: `SpudUserActivity` factory + decoder

**Files:**
- Create: `Spud/Integration/SpudUserActivity.swift`
- Test: `SpudTests/SpudUserActivityTests.swift`

**Interfaces:**
- Produces: `enum SpudUserActivity` with `static let viewPostType/viewCommunityType/viewPersonType: String`, `static let allTypes: [String]`, `static func viewPost(routingURL:title:) -> NSUserActivity`, `viewCommunity(routingURL:name:) -> NSUserActivity`, `viewPerson(routingURL:handle:) -> NSUserActivity`, and `static func routingURL(from: NSUserActivity) -> URL?`.

- [ ] **Step 1: Write the failing test**

```swift
// SpudTests/SpudUserActivityTests.swift
import CoreSpotlight
import XCTest
@testable import Spud

final class SpudUserActivityTests: XCTestCase {
    private let postURL = URL(string: "info.ddenis.spud://internal/resolve?url=https://lemmy.world/post/5")!

    func test_viewPost_setsTypeURLAndEligibility() {
        let activity = SpudUserActivity.viewPost(routingURL: postURL, title: "Hello")
        XCTAssertEqual(activity.activityType, SpudUserActivity.viewPostType)
        XCTAssertEqual(activity.userInfo?["url"] as? String, postURL.absoluteString)
        XCTAssertEqual(activity.persistentIdentifier, postURL.absoluteString)
        XCTAssertTrue(activity.isEligibleForHandoff)
        XCTAssertTrue(activity.isEligibleForSearch)
        XCTAssertTrue(activity.isEligibleForPrediction)
    }

    func test_routingURL_decodesOwnActivity() {
        let activity = SpudUserActivity.viewPost(routingURL: postURL, title: "Hello")
        XCTAssertEqual(SpudUserActivity.routingURL(from: activity), postURL)
    }

    func test_routingURL_decodesSpotlightItemTap() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: postURL.absoluteString]
        XCTAssertEqual(SpudUserActivity.routingURL(from: activity), postURL)
    }

    func test_routingURL_returnsNilForUnknownActivity() {
        let activity = NSUserActivity(activityType: "com.example.other")
        XCTAssertNil(SpudUserActivity.routingURL(from: activity))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: FAIL — `SpudUserActivity` not found (and `make project` needed once the new file exists).

- [ ] **Step 3: Write minimal implementation**

```swift
// Spud/Integration/SpudUserActivity.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreSpotlight
import Foundation

/// Builds and decodes the `NSUserActivity` objects Spud vends from content
/// screens. Every activity carries the canonical routing URL
/// (`info.ddenis.spud://internal/...`) in `userInfo["url"]`, so continuation and
/// Spotlight taps funnel through the same `AppCoordinator.open` path as deep
/// links. Pure value logic (no database / UIKit dependency) so it is
/// unit-testable in isolation.
enum SpudUserActivity {
    static let viewPostType = "info.ddenis.Spud.viewPost"
    static let viewCommunityType = "info.ddenis.Spud.viewCommunity"
    static let viewPersonType = "info.ddenis.Spud.viewPerson"

    /// `userInfo` key holding the routing URL string.
    static let routingURLKey = "url"

    /// Our own activity types (also declared in `Info.plist`'s `NSUserActivityTypes`).
    static let allTypes = [viewPostType, viewCommunityType, viewPersonType]

    static func viewPost(routingURL: URL, title: String) -> NSUserActivity {
        make(type: viewPostType, routingURL: routingURL, title: title)
    }

    static func viewCommunity(routingURL: URL, name: String) -> NSUserActivity {
        make(type: viewCommunityType, routingURL: routingURL, title: "!\(name)")
    }

    static func viewPerson(routingURL: URL, handle: String) -> NSUserActivity {
        make(type: viewPersonType, routingURL: routingURL, title: handle)
    }

    private static func make(type: String, routingURL: URL, title: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.userInfo = [routingURLKey: routingURL.absoluteString]
        activity.keywords = Set(title.split(separator: " ").map(String.init))
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = routingURL.absoluteString
        return activity
    }

    /// Decodes the routing URL from a continued activity: either one of our own
    /// activities (URL in `userInfo`) or a Spotlight item tap
    /// (`CSSearchableItemActionType`, identifier in
    /// `CSSearchableItemActivityIdentifier`).
    static func routingURL(from activity: NSUserActivity) -> URL? {
        if activity.activityType == CSSearchableItemActionType,
           let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            return URL(string: identifier)
        }
        if allTypes.contains(activity.activityType),
           let urlString = activity.userInfo?[routingURLKey] as? String {
            return URL(string: urlString)
        }
        return nil
    }
}
```

- [ ] **Step 4: Regenerate project, run test to verify it passes**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: PASS (all four `SpudUserActivityTests`).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Integration/SpudUserActivity.swift SpudTests/SpudUserActivityTests.swift
git add Spud/Integration/SpudUserActivity.swift SpudTests/SpudUserActivityTests.swift
git commit -m "feat(integration): add SpudUserActivity factory and decoder"
```

---

### Task 2: Vend the post activity from `PostDetailViewController`

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (existing `viewDidAppear` ~lines 263-270; add `viewDidDisappear` + `updateUserActivity`)

**Interfaces:**
- Consumes: `SpudUserActivity.viewPost(routingURL:title:)`; `ShareURL.forPost(originalPostUrl:serverPostId:instanceActorId:)`; `appDatabase.accountInstanceActorIdSync(forKeychainId:)`; `SpudInternalLink.objectAtURL(url:)`.

No unit test (UIKit lifecycle wiring) — verified by build + the manual Handoff pass in Task 6.

- [ ] **Step 1: Add the import (if missing)**

Ensure the file imports `SpudUtilKit` (for `SpudInternalLink`). Check the existing import block; add `import SpudUtilKit` only if not already present.

- [ ] **Step 2: Edit `viewDidAppear` and add lifecycle + helper**

Append `updateUserActivity()` to the existing `viewDidAppear(_:)`, and add the two new methods near it:

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if isFirstAppearance, preferencesService.markPostsRead {
        Task { await markAsRead() }
    }
    isFirstAppearance = false

    updateUserActivity()
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    userActivity?.resignCurrent()
    userActivity = nil
}

/// Vends a Handoff/Spotlight/Prediction activity for this post, keyed by its
/// canonical `ap_id` so it resolves under any account on any device.
private func updateUserActivity() {
    let instanceActorId = appDatabase.accountInstanceActorIdSync(
        forKeychainId: viewModel.accountKeychainId
    )
    guard let canonical = ShareURL.forPost(
        originalPostUrl: headerRow?.originalPostUrl,
        serverPostId: Int64(viewModel.serverPostId),
        instanceActorId: instanceActorId
    ) else { return }
    let routingURL = SpudInternalLink.objectAtURL(url: canonical).url
    let activity = SpudUserActivity.viewPost(
        routingURL: routingURL,
        title: headerRow?.title ?? "Post"
    )
    userActivity = activity
    activity.becomeCurrent()
}
```

Note: if `headerRow?.title` does not exist on `PostDetailHeaderRow`, substitute the row's title field (grep `struct PostDetailHeaderRow` for the title-bearing property) — keep the `?? "Post"` fallback either way.

- [ ] **Step 3: Build to verify it compiles**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED, 0 new warnings.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat(post-detail): vend an NSUserActivity for the open post"
```

---

### Task 3: Vend the community activity from `CommunityViewController`

**Files:**
- Modify: `Spud/Scenes/Community/Content/CommunityViewController.swift` (add `viewDidAppear`/`viewDidDisappear`/`updateUserActivity`)

**Interfaces:**
- Consumes: `SpudUserActivity.viewCommunity(routingURL:name:)`; `SpudInternalLink.community(name:instance:)`; `InstanceActorId(from: URL)`; `viewModel.name`, `viewModel.actorId`.

- [ ] **Step 1: Ensure `import SpudUtilKit`** is present (for `InstanceActorId` + `SpudInternalLink`); add if missing.

- [ ] **Step 2: Add lifecycle + helper**

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateUserActivity()
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    userActivity?.resignCurrent()
    userActivity = nil
}

/// Vends a Handoff/Spotlight/Prediction activity for this community, keyed by
/// `!name@instance` so it resolves without a network round-trip.
private func updateUserActivity() {
    guard
        !viewModel.name.isEmpty,
        let actorId = viewModel.actorId,
        let url = URL(string: actorId),
        let instance = InstanceActorId(from: url)
    else { return }
    let routingURL = SpudInternalLink.community(name: viewModel.name, instance: instance).url
    let activity = SpudUserActivity.viewCommunity(routingURL: routingURL, name: viewModel.name)
    userActivity = activity
    activity.becomeCurrent()
}
```

If `CommunityViewController` already overrides `viewDidAppear`/`viewDidDisappear`, fold the `updateUserActivity()` / `resignCurrent()` calls into the existing overrides instead of redeclaring them.

- [ ] **Step 3: Build to verify it compiles**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/Community/Content/CommunityViewController.swift
git add Spud/Scenes/Community/Content/CommunityViewController.swift
git commit -m "feat(community): vend an NSUserActivity for the open community"
```

---

### Task 4: `personActorIdSync` query

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/PersonQueries.swift`
- Test: `SpudDataKitTests/PersonQueriesTests.swift`

**Interfaces:**
- Produces: `AppDatabase.personActorIdSync(forServerPersonId: Int64) -> String?` (off-main; the person's `ap_id` / actor URL, or nil).

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/PersonQueriesTests.swift
import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class PersonQueriesTests: XCTestCase {
    func test_personActorIdSync_returnsActorId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://lemmy.world', ?)", arguments: [Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO person (siteId, personId, name, actorId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 42, 'alice', 'https://lemmy.world/u/alice', 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
        }
        XCTAssertEqual(appDatabase.personActorIdSync(forServerPersonId: 42), "https://lemmy.world/u/alice")
        XCTAssertNil(appDatabase.personActorIdSync(forServerPersonId: 999))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudDataKit`
Expected: FAIL — `personActorIdSync` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// SpudDataKit/Services/AppDatabase/PersonQueries.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// The federation actor id (`ap_id`) for a person identified by its server
    /// id, for the first matching row. A one-shot synchronous read, safe off the
    /// main thread (used by the Person screen to vend an NSUserActivity). nil
    /// when unknown or the column is empty.
    func personActorIdSync(forServerPersonId serverPersonId: Int64) -> String? {
        (try? writer.read { db -> String? in
            try String.fetchOne(
                db,
                sql: "SELECT actorId FROM person WHERE personId = ? LIMIT 1",
                arguments: [serverPersonId]
            )
        }) ?? nil
    }
}
```

- [ ] **Step 4: Regenerate, run test to verify it passes**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudDataKit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/PersonQueries.swift SpudDataKitTests/PersonQueriesTests.swift
git add SpudDataKit/Services/AppDatabase/PersonQueries.swift SpudDataKitTests/PersonQueriesTests.swift
git commit -m "feat(data): add personActorIdSync off-main read"
```

---

### Task 5: Vend the person activity from `PersonViewController`

**Files:**
- Modify: `Spud/Scenes/Person/Content/PersonViewController.swift`

**Interfaces:**
- Consumes: `appDatabase.personActorIdSync(forServerPersonId:)` (Task 4); `SpudUserActivity.viewPerson(routingURL:handle:)`; `SpudInternalLink.objectAtURL(url:)`; `viewModel.serverPersonId`, `viewModel.handle`; the VC's `appDatabase`.

- [ ] **Step 1: Confirm the VC holds an `appDatabase`** — grep `PersonViewController.swift` for `appDatabase`. If the dependency is reachable only via the view model, route the call through whatever exposes `AppDatabase` (mirror how `CommunityViewController`/`PostDetailViewController` reach `appDatabase`). Add `import SpudUtilKit` if missing.

- [ ] **Step 2: Add lifecycle + helper**

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateUserActivity()
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    userActivity?.resignCurrent()
    userActivity = nil
}

/// Vends a Handoff/Spotlight/Prediction activity for this person, keyed by
/// their canonical `ap_id` (resolved via the existing `.objectAtURL` path).
private func updateUserActivity() {
    guard
        let actorIdString = appDatabase.personActorIdSync(forServerPersonId: Int64(viewModel.serverPersonId)),
        let actorURL = URL(string: actorIdString)
    else { return }
    let routingURL = SpudInternalLink.objectAtURL(url: actorURL).url
    let activity = SpudUserActivity.viewPerson(routingURL: routingURL, handle: viewModel.handle)
    userActivity = activity
    activity.becomeCurrent()
}
```

If `PersonViewController` already overrides these lifecycle methods, fold the calls in rather than redeclaring.

- [ ] **Step 3: Build to verify it compiles**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/Person/Content/PersonViewController.swift
git add Spud/Scenes/Person/Content/PersonViewController.swift
git commit -m "feat(person): vend an NSUserActivity for the open profile"
```

---

### Task 6: SceneDelegate continuation + Info.plist

**Files:**
- Modify: `Spud/App/SceneDelegate.swift` (add `scene(_:continue:)`, cold-launch userActivity handling in `scene(_:willConnectTo:options:)`, shared router helper)
- Modify: `Spud/Resources/Info.plist` (`NSUserActivityTypes`)

**Interfaces:**
- Consumes: `SpudUserActivity.routingURL(from:)`; `AppCoordinator.shared.open(_:in:)`.

Decoder logic is unit-tested in Task 1; this task is verified by build + the manual Handoff/Spotlight pass.

- [ ] **Step 1: Replace the stale `NSUserActivityTypes` in `Info.plist`**

Replace:
```xml
<key>NSUserActivityTypes</key>
<array>
    <string>ViewTopPostsIntent</string>
</array>
```
with:
```xml
<key>NSUserActivityTypes</key>
<array>
    <string>info.ddenis.Spud.viewPost</string>
    <string>info.ddenis.Spud.viewCommunity</string>
    <string>info.ddenis.Spud.viewPerson</string>
</array>
```

- [ ] **Step 2: Add the continuation handler + shared router in `SceneDelegate`**

Add a `scene(_:continue:)` method and a private router, and call the router for a cold-launch activity inside `scene(_:willConnectTo:options:)` (after `setActiveWindow(window)` and the existing `urlContexts` block, before `makeKeyAndVisible()`):

```swift
// Inside scene(_:willConnectTo:options:), after the urlContexts handling:
if let activity = connectionOptions.userActivities.first {
    routeContinuedActivity(activity, in: window)
}
```

```swift
// New methods on SceneDelegate:
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard let window else {
        logger.assertionFailure("Huh, no window?")
        return
    }
    routeContinuedActivity(userActivity, in: window)
}

/// Decodes a continued NSUserActivity (our own Handoff activities or a Spotlight
/// item tap) into a routing URL and opens it like any deep link.
private func routeContinuedActivity(_ userActivity: NSUserActivity, in window: MainWindow) {
    guard let url = SpudUserActivity.routingURL(from: userActivity) else {
        logger.debug("Ignoring continued activity \(userActivity.activityType, privacy: .public)")
        return
    }
    AppCoordinator.shared.open(url, in: window)
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/App/SceneDelegate.swift
git add Spud/App/SceneDelegate.swift Spud/Resources/Info.plist
git commit -m "feat(scene): continue user activities and Spotlight taps via AppCoordinator"
```

- [ ] **Step 5: Manual verification (Slice 1)** — on device/sim: open a post, background the app, confirm a Handoff banner appears on a paired device (or that the activity is the current one); tap a Spotlight result later (after Slice 3) and confirm it opens the right screen. Record results; defer cross-device Handoff to the end-of-branch manual pass if no paired device is available.

---

# Slice 2 — App Intents completion

### Task 7: `AppNavigation.savedFeed` routing

**Files:**
- Modify: `Spud/App/AppNavigation.swift` (enum case + protocol method)
- Modify: `Spud/App/AppCoordinator.swift` (`apply` switch)
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (`selectSavedFeed`)
- Test: `SpudTests/AppNavigationRoutingTests.swift` (spy method + test)

**Interfaces:**
- Produces: `AppNavigation.savedFeed(sort: Components.Schemas.SortType?)`; `AppNavigating.selectSavedFeed(sort: Components.Schemas.SortType?)`.

- [ ] **Step 1: Write the failing test** — extend `AppNavigationRoutingTests`:

Add to `SpyNavigator`:
```swift
func selectSavedFeed(sort: Components.Schemas.SortType?) {
    calls.append("savedFeed:\(String(describing: sort))")
}
```
Add a test:
```swift
func test_navigate_savedFeed_routesToSavedFeed() {
    let coordinator = AppCoordinator.shared
    let spy = SpyNavigator()
    coordinator.setActiveWindow(spy)

    coordinator.navigate(.savedFeed(sort: nil))

    XCTAssertEqual(spy.calls, ["savedFeed:nil"])
    coordinator.setActiveWindow(nil)
}
```

- [ ] **Step 2: Run test to verify it fails** (build error: `savedFeed` not a member / protocol unsatisfied).

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: FAIL (compile error referencing `.savedFeed`).

- [ ] **Step 3: Add the enum case + protocol requirement** in `AppNavigation.swift`:

```swift
enum AppNavigation: Equatable {
    case feed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?)
    case search(query: String)
    case newPost
    case inbox
    case community(name: String, instance: InstanceActorId)
    case savedFeed(sort: Components.Schemas.SortType?)
}

@MainActor
protocol AppNavigating: AnyObject {
    func selectFeed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?)
    func selectSearch(query: String)
    func presentNewPost()
    func selectInbox()
    func display(communityName: String, instance: InstanceActorId, accountKeychainId: String)
    func selectSavedFeed(sort: Components.Schemas.SortType?)
}
```

- [ ] **Step 4: Handle the case** in `AppCoordinator.apply(_:to:)`:

```swift
case let .savedFeed(sort):
    window.selectSavedFeed(sort: sort)
```

- [ ] **Step 5: Implement `selectSavedFeed`** in `MainWindow` (mirror `selectFeed`, lines ~436-444):

```swift
func selectSavedFeed(sort: Components.Schemas.SortType?) {
    tabBarController.selectedIndex = 0
    let postListVC = splitViewController?.postListNavigationController
        .viewControllers.first as? PostListViewController
    postListVC?.showFeed(.saved(sortType: sort ?? .Hot))
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: PASS (`test_navigate_savedFeed_routesToSavedFeed` + existing routing tests still green).

- [ ] **Step 7: Commit**

```bash
mint run swiftformat Spud/App/AppNavigation.swift Spud/App/AppCoordinator.swift Spud/Scenes/MainWindow/MainWindow.swift SpudTests/AppNavigationRoutingTests.swift
git add Spud/App/AppNavigation.swift Spud/App/AppCoordinator.swift Spud/Scenes/MainWindow/MainWindow.swift SpudTests/AppNavigationRoutingTests.swift
git commit -m "feat(navigation): add savedFeed navigation target"
```

---

### Task 8: `OpenSavedAppIntent` + App Shortcut

**Files:**
- Create: `Spud/Intents/OpenSavedAppIntent.swift`
- Modify: `Spud/Intents/SpudAppShortcuts.swift`

**Interfaces:**
- Consumes: `AppCoordinator.shared.navigate(.savedFeed(sort:))` (Task 7).

- [ ] **Step 1: Create the intent**

```swift
// Spud/Intents/OpenSavedAppIntent.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Opens the Saved feed. Signed-out is handled in-app (the Saved feed already
/// gates), so this intent always opens the app and selects the feed.
struct OpenSavedAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Saved Posts"
    static let description = IntentDescription("Open your saved posts in Spud.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.navigate(.savedFeed(sort: nil))
        return .result()
    }
}
```

- [ ] **Step 2: Add the shortcut** to `SpudAppShortcuts.appShortcuts` (after the existing entries):

```swift
AppShortcut(
    intent: OpenSavedAppIntent(),
    phrases: [
        "Open my \(.applicationName) saved posts",
        "Show saved in \(.applicationName)",
    ],
    shortTitle: "Saved Posts",
    systemImageName: "bookmark.fill"
)
```

- [ ] **Step 3: Regenerate + build**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Intents/OpenSavedAppIntent.swift Spud/Intents/SpudAppShortcuts.swift
git add Spud/Intents/OpenSavedAppIntent.swift Spud/Intents/SpudAppShortcuts.swift
git commit -m "feat(intents): add Open Saved app intent and shortcut"
```

---

### Task 9: `accountsSync` off-main read

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/AccountQueries.swift`
- Test: `SpudDataKitTests/AccountQueriesTests.swift`

**Interfaces:**
- Produces: `AppDatabase.accountsSync() -> [AccountListRow]` (non-service accounts, off-main; reuses the existing `AccountListRow` type).

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/AccountQueriesTests.swift
import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class AccountQueriesTests: XCTestCase {
    private static func seedAccount(_ db: Database, keychainId: String, host: String, isDefault: Bool, signedOut: Bool) throws {
        try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(host)", Date()])
        let instanceId = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
        let siteId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
            VALUES (?, ?, ?, 0, ?, ?, ?)
            """, arguments: [siteId, keychainId, isDefault, signedOut, Date(), Date()])
    }

    func test_accountsSync_returnsNonServiceAccountsWithHosts() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            try Self.seedAccount(db, keychainId: "kc-1", host: "lemmy.world", isDefault: true, signedOut: false)
            try Self.seedAccount(db, keychainId: "kc-2", host: "beehaw.org", isDefault: false, signedOut: true)
        }
        let rows = appDatabase.accountsSync()
        XCTAssertEqual(Set(rows.map(\.accountKeychainId)), ["kc-1", "kc-2"])
        XCTAssertEqual(Set(rows.map(\.instanceHostname)), ["lemmy.world", "beehaw.org"])
        XCTAssertEqual(rows.first(where: { $0.accountKeychainId == "kc-1" })?.isDefault, true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudDataKit`
Expected: FAIL — `accountsSync` not found.

- [ ] **Step 3: Write minimal implementation** (one-shot mirror of `observeAccountListRows`):

```swift
// SpudDataKit/Services/AppDatabase/AccountQueries.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// One-shot synchronous read of the non-service accounts, ordered like
    /// `observeAccountListRows`. Safe off the main thread, for the App Intents
    /// `AccountAppEntity` query (a background process) which cannot touch the
    /// `@MainActor` `AccountService`.
    func accountsSync() -> [AccountListRow] {
        (try? writer.read { db -> [AccountListRow] in
            let rows = try Row.fetchAll(db, sql: """
                    SELECT
                        account.id              AS accountId,
                        account.accountKeychainId AS accountKeychainId,
                        account.isDefault       AS isDefault,
                        account.isSignedOutAccountType AS isSignedOutAccountType,
                        account.email           AS email,
                        instance.actorId        AS instanceActorId,
                        person.name             AS personName,
                        person.displayName      AS personDisplayName
                    FROM account
                    JOIN site     ON site.id = account.siteId
                    JOIN instance ON instance.id = site.instanceId
                    LEFT JOIN person ON person.id = account.personId
                    WHERE account.isServiceAccount = 0
                    ORDER BY account.isSignedOutAccountType ASC,
                             account.accountKeychainId ASC
                """)
            return rows.map { row in
                let actorId: String = row["instanceActorId"]
                let host = URL(string: actorId)?.host ?? actorId
                let nickname = row.coalescingString("personDisplayName", "personName")
                return AccountListRow(
                    id: row["accountId"],
                    accountKeychainId: row["accountKeychainId"],
                    isDefault: row["isDefault"],
                    isSignedOutAccountType: row["isSignedOutAccountType"],
                    instanceHostname: host,
                    nickname: nickname,
                    email: row["email"]
                )
            }
        }) ?? []
    }
}
```

- [ ] **Step 4: Regenerate, run test to verify it passes**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudDataKit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/AccountQueries.swift SpudDataKitTests/AccountQueriesTests.swift
git add SpudDataKit/Services/AppDatabase/AccountQueries.swift SpudDataKitTests/AccountQueriesTests.swift
git commit -m "feat(data): add accountsSync off-main read"
```

---

### Task 10: `AccountAppEntity` + `AccountEntityQuery`

**Files:**
- Create: `Spud/Intents/AccountAppEntity.swift`
- Create: `Spud/Intents/AccountEntityQuery.swift`
- Test: `SpudTests/AccountEntityQueryTests.swift`

**Interfaces:**
- Consumes: `AppDatabase.accountsSync()` (Task 9); `AccountListRow`.
- Produces: `struct AccountAppEntity: AppEntity` (`id: String` = `accountKeychainId`, `nickname: String`, `instanceHost: String`, `init(row: AccountListRow)`); `struct AccountEntityQuery: EntityQuery` with `init()` and `init(load: @escaping @Sendable () -> [AccountAppEntity])`.

- [ ] **Step 1: Write the failing test** (mirror `CommunityEntityQueryTests` — pure filtering, no GRDB):

```swift
// SpudTests/AccountEntityQueryTests.swift
import XCTest
@testable import Spud

final class AccountEntityQueryTests: XCTestCase {
    private let world = AccountAppEntity(id: "kc-1", nickname: "alice", instanceHost: "lemmy.world")
    private let beehaw = AccountAppEntity(id: "kc-2", nickname: "bob", instanceHost: "beehaw.org")

    private func query() -> AccountEntityQuery {
        let entities = [world, beehaw]
        return AccountEntityQuery(load: { entities })
    }

    func test_suggestedEntities_returnsAll() async throws {
        let result = try await query().suggestedEntities()
        XCTAssertEqual(result.map(\.id), ["kc-1", "kc-2"])
    }

    func test_entitiesForIds_roundTripsById() async throws {
        let result = try await query().entities(for: ["kc-2"])
        XCTAssertEqual(result.map(\.id), ["kc-2"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (`AccountAppEntity`/`AccountEntityQuery` not found).

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: FAIL.

- [ ] **Step 3: Create `AccountAppEntity`**

```swift
// Spud/Intents/AccountAppEntity.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import SpudDataKit

/// A Spud account exposed to App Intents / Siri. Identity is the durable
/// `accountKeychainId`, so switching is stable across re-imports and federation.
struct AccountAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = AccountEntityQuery()

    var id: String
    var nickname: String
    var instanceHost: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(nickname)", subtitle: "\(instanceHost)")
    }
}

extension AccountAppEntity {
    /// Builds an entity from an account list row. Falls back to the instance
    /// host when there is no signed-in nickname (signed-out browsing accounts).
    init(row: AccountListRow) {
        self.init(
            id: row.accountKeychainId,
            nickname: row.nickname ?? row.instanceHostname,
            instanceHost: row.instanceHostname
        )
    }
}
```

- [ ] **Step 4: Create `AccountEntityQuery`** (injected-closure pattern, mirror `CommunityEntityQuery`):

```swift
// Spud/Intents/AccountEntityQuery.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import SpudDataKit

/// Resolves `AccountAppEntity` values from the accounts in the shared App-Group
/// database. Runs in a background intents process, so it opens its own read-only
/// data path (like the widget) rather than the app's UI coordinator. Tests
/// inject `load` to avoid touching the shared store.
struct AccountEntityQuery: EntityQuery {
    private let load: @Sendable () -> [AccountAppEntity]

    init() {
        load = { AccountEntityQuery.loadFromSharedDatabase() }
    }

    init(load: @escaping @Sendable () -> [AccountAppEntity]) {
        self.load = load
    }

    func entities(for identifiers: [String]) async throws -> [AccountAppEntity] {
        let wanted = Set(identifiers)
        return load().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountAppEntity] {
        load()
    }

    private static func loadFromSharedDatabase() -> [AccountAppEntity] {
        guard let appDatabase = try? AppDatabase() else { return [] }
        return appDatabase.accountsSync().map(AccountAppEntity.init(row:))
    }
}
```

- [ ] **Step 5: Regenerate, run test to verify it passes**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
mint run swiftformat Spud/Intents/AccountAppEntity.swift Spud/Intents/AccountEntityQuery.swift SpudTests/AccountEntityQueryTests.swift
git add Spud/Intents/AccountAppEntity.swift Spud/Intents/AccountEntityQuery.swift SpudTests/AccountEntityQueryTests.swift
git commit -m "feat(intents): add AccountAppEntity and entity query"
```

---

### Task 11: `SwitchAccountAppIntent` + App Shortcut

**Files:**
- Create: `Spud/Intents/SwitchAccountAppIntent.swift`
- Modify: `Spud/Intents/SpudAppShortcuts.swift`

**Interfaces:**
- Consumes: `AccountAppEntity` (Task 10); `AppCoordinator.shared.dependencies.accountService.setDefaultAccount(forAccountKeychainId:)`.

- [ ] **Step 1: Create the intent**

```swift
// Spud/Intents/SwitchAccountAppIntent.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Switches the active Spud account. The existing default-account observation
/// rebuilds the UI for the new default.
struct SwitchAccountAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Account"
    static let description = IntentDescription("Switch the active Spud account.")
    static let openAppWhenRun = true

    @Parameter(title: "Account")
    var account: AccountAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.dependencies.accountService
            .setDefaultAccount(forAccountKeychainId: account.id)
        return .result()
    }
}
```

- [ ] **Step 2: Add the shortcut** to `SpudAppShortcuts.appShortcuts`:

```swift
AppShortcut(
    intent: SwitchAccountAppIntent(),
    phrases: [
        "Switch to \(\.$account) in \(.applicationName)",
        "Switch \(.applicationName) account",
    ],
    shortTitle: "Switch Account",
    systemImageName: "person.crop.circle"
)
```

- [ ] **Step 3: Regenerate + build**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Intents/SwitchAccountAppIntent.swift Spud/Intents/SpudAppShortcuts.swift
git add Spud/Intents/SwitchAccountAppIntent.swift Spud/Intents/SpudAppShortcuts.swift
git commit -m "feat(intents): add Switch Account app intent and shortcut"
```

---

### Task 12: Per-community Siri donation

**Files:**
- Modify: `Spud/Intents/OpenCommunityAppIntent.swift`

**Interfaces:**
- Consumes: `IntentDonationManager.shared.donate(intent:)`.

- [ ] **Step 1: Verify the `IntentDonationManager.donate` signature on the pinned SDK** — use the `ddenis:apple-docs` skill (Sosumi MCP) to confirm `IntentDonationManager.shared.donate(intent:)` is `async`, non-throwing, `@discardableResult`. Adjust the `await`/`try` in Step 2 to match what the docs show.

- [ ] **Step 2: Add the donation** to `perform()` (before `return .result()`):

```swift
@MainActor
func perform() async throws -> some IntentResult {
    AppCoordinator.shared.navigate(.community(name: community.name, instance: community.instance))
    _ = await IntentDonationManager.shared.donate(intent: self)
    return .result()
}
```

If Step 1 shows the method throws, use `_ = try? await IntentDonationManager.shared.donate(intent: self)`.

- [ ] **Step 3: Build to verify it compiles**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Intents/OpenCommunityAppIntent.swift
git add Spud/Intents/OpenCommunityAppIntent.swift
git commit -m "feat(intents): donate OpenCommunity intent for Siri prediction"
```

---

# Slice 3 — Spotlight indexing of saved + history

### Task 13: `SpotlightContentQueries`

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/SpotlightContentQueries.swift`
- Test: `SpudDataKitTests/SpotlightContentQueriesTests.swift`

**Interfaces:**
- Produces: `struct IndexableContentRow: Sendable, Equatable` (`serverPostId: Int64`, `title: String`, `originalPostUrl: String?`, `thumbnailUrl: String?`, `communityName: String?`); `AppDatabase.indexableContentRowsSync(forKeychainId:limit:) -> [IndexableContentRow]`; `AppDatabase.indexableContentRowsForDefaultAccountSync(limit:) -> [IndexableContentRow]`.

- [ ] **Step 1: Write the failing test** (mirror `HistoryObservationsTests` seed helpers):

```swift
// SpudDataKitTests/SpotlightContentQueriesTests.swift
import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class SpotlightContentQueriesTests: XCTestCase {
    private static func seedGraph(_ db: Database, keychainId: String, isDefault: Bool) throws -> (accountId: Int64, communityId: Int64, personId: Int64) {
        try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
        let instanceId = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
        let siteId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO person (siteId, personId, name, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
            VALUES (?, 10, 'alice', 0, 0, 0, 0, 0, 0, 0, ?, ?)
            """, arguments: [siteId, Date(), Date()])
        let personId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
            VALUES (?, ?, ?, 0, 0, ?, ?)
            """, arguments: [siteId, keychainId, isDefault, Date(), Date()])
        let accountId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods, isRemoved, subscribedState, numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
            VALUES (?, 5, 'programming', 'https://\(keychainId).test/c/programming', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
            """, arguments: [accountId, Date(), Date()])
        let communityId = db.lastInsertedRowID
        return (accountId, communityId, personId)
    }

    private static func insertPost(_ db: Database, accountId: Int64, communityId: Int64, personId: Int64, serverPostId: Int64, title: String, isSaved: Bool) throws {
        try db.execute(sql: """
            INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl, score, numberOfUpvotes, numberOfDownvotes, numberOfComments, isRead, isSaved, isHidden, isRemoved, isLocked, isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, 'https://x.test/post/\(serverPostId)', 7, 7, 0, 3, 0, ?, 0, 0, 0, 0, 0, 0, ?, ?, ?)
            """, arguments: [accountId, communityId, personId, serverPostId, title, isSaved, Date(), Date(), Date()])
    }

    private static func insertInteraction(_ db: Database, accountId: Int64, postServerId: Int64, title: String, lastOpenedAt: Date?) throws {
        var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.titleSnapshot = title
        record.communityName = "programming"
        record.lastOpenedAt = lastOpenedAt
        try record.insert(db)
    }

    func test_indexableRows_returnsSavedAndRecentOpened() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-1", isDefault: true)
            // 1: saved but never opened -> included (saved)
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Saved", isSaved: true)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Saved", lastOpenedAt: nil)
            // 2: opened but not saved -> included (recent)
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Opened", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Opened", lastOpenedAt: Date(timeIntervalSince1970: 1_000_000))
            // 3: only seen (never opened, not saved) -> excluded
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 3, title: "OnlySeen", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 3, title: "OnlySeen", lastOpenedAt: nil)
        }
        let rows = appDatabase.indexableContentRowsSync(forKeychainId: "kc-1", limit: 100)
        XCTAssertEqual(Set(rows.map(\.serverPostId)), [1, 2])
        let saved = rows.first { $0.serverPostId == 1 }
        XCTAssertEqual(saved?.title, "Saved")
        XCTAssertEqual(saved?.originalPostUrl, "https://x.test/post/1")
        XCTAssertEqual(saved?.communityName, "programming")
    }

    func test_indexableRowsForDefaultAccount_resolvesDefault() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-default", isDefault: true)
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Saved", isSaved: true)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Saved", lastOpenedAt: nil)
        }
        let rows = appDatabase.indexableContentRowsForDefaultAccountSync(limit: 100)
        XCTAssertEqual(rows.map(\.serverPostId), [1])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudDataKit`
Expected: FAIL — `indexableContentRowsSync` not found.

- [ ] **Step 3: Write minimal implementation** (join mirrors `observeHistoryRows`; `Self.accountRowId(forKeychainId:in:)` and the default-account resolution mirror existing helpers):

```swift
// SpudDataKit/Services/AppDatabase/SpotlightContentQueries.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A row to index into Spotlight: a saved or recently-opened post, with the
/// fields needed to build a `CSSearchableItem` and its routing URL.
public struct IndexableContentRow: Sendable, Equatable {
    public let serverPostId: Int64
    public let title: String
    public let originalPostUrl: String?
    public let thumbnailUrl: String?
    public let communityName: String?
}

public extension AppDatabase {
    /// Saved posts plus the most recently opened posts for the account, newest
    /// first, capped at `limit`. One-shot synchronous read, safe off the main
    /// thread. Joins `postInteraction -> post -> community` (saved state and the
    /// canonical `ap_id` live on `post`, not `postInteraction`).
    func indexableContentRowsSync(forKeychainId keychainId: String, limit: Int) -> [IndexableContentRow] {
        (try? writer.read { db -> [IndexableContentRow] in
            guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                return []
            }
            let rows = try Row.fetchAll(db, sql: """
                    SELECT
                        post.postId          AS serverPostId,
                        post.title           AS title,
                        post.originalPostUrl AS originalPostUrl,
                        post.thumbnailUrl    AS thumbnailUrl,
                        community.name       AS communityName
                    FROM postInteraction
                    JOIN post      ON post.accountId = postInteraction.accountId AND post.postId = postInteraction.postServerId
                    JOIN community ON community.id = post.communityId
                    WHERE postInteraction.accountId = ?
                      AND (post.isSaved = 1 OR postInteraction.lastOpenedAt IS NOT NULL)
                    ORDER BY post.isSaved DESC, postInteraction.lastOpenedAt DESC
                    LIMIT ?
                """, arguments: [accountId, limit])
            return rows.map { row in
                IndexableContentRow(
                    serverPostId: row["serverPostId"],
                    title: row["title"] ?? "",
                    originalPostUrl: row["originalPostUrl"],
                    thumbnailUrl: row["thumbnailUrl"],
                    communityName: row["communityName"]
                )
            }
        }) ?? []
    }

    /// `indexableContentRowsSync` for the default (non-service) account. Mirrors
    /// `followedCommunitiesForDefaultAccountSync`'s default-account resolution.
    func indexableContentRowsForDefaultAccountSync(limit: Int) -> [IndexableContentRow] {
        let keychainId = (try? writer.read { db -> String? in
            try AccountRecord
                .filter(Column("isServiceAccount") == false)
                .order(sql: "isDefault DESC, id ASC")
                .fetchOne(db)?
                .accountKeychainId
        }) ?? nil
        guard let keychainId else { return [] }
        return indexableContentRowsSync(forKeychainId: keychainId, limit: limit)
    }
}
```

If `Self.accountRowId(forKeychainId:in:)` is not visible from this file (it is used inside `HistoryObservations.swift`), grep for its declaration and match the call exactly.

- [ ] **Step 4: Regenerate, run test to verify it passes**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudDataKit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/SpotlightContentQueries.swift SpudDataKitTests/SpotlightContentQueriesTests.swift
git add SpudDataKit/Services/AppDatabase/SpotlightContentQueries.swift SpudDataKitTests/SpotlightContentQueriesTests.swift
git commit -m "feat(data): add indexable saved+history content reads"
```

---

### Task 14: `ContentSpotlightIndexer`

**Files:**
- Create: `Spud/Integration/ContentSpotlightIndexer.swift`
- Test: `SpudTests/ContentSpotlightIndexerTests.swift`

**Interfaces:**
- Consumes: `AppDatabase.indexableContentRowsForDefaultAccountSync(limit:)` (Task 13); `IndexableContentRow`; `ShareURL.forPost(...)`; `SpudInternalLink.objectAtURL(url:)`.
- Produces: `enum ContentSpotlightIndexer` with `static let domainIdentifier = "content"`, `static func makeItem(from: IndexableContentRow) -> CSSearchableItem?`, `static func reindex(appDatabase: AppDatabase)`.

- [ ] **Step 1: Write the failing test** (pure mapping):

```swift
// SpudTests/ContentSpotlightIndexerTests.swift
import XCTest
@testable import Spud
@testable import SpudDataKit
import SpudUtilKit

final class ContentSpotlightIndexerTests: XCTestCase {
    func test_makeItem_buildsRoutingIdentifierAndTitle() throws {
        let row = IndexableContentRow(
            serverPostId: 5,
            title: "Hello world",
            originalPostUrl: "https://lemmy.world/post/5",
            thumbnailUrl: "https://lemmy.world/pic.jpg",
            communityName: "programming"
        )
        let item = try XCTUnwrap(ContentSpotlightIndexer.makeItem(from: row))

        let expected = SpudInternalLink.objectAtURL(url: URL(string: "https://lemmy.world/post/5")!).url.absoluteString
        XCTAssertEqual(item.uniqueIdentifier, expected)
        XCTAssertEqual(item.domainIdentifier, "content")
        XCTAssertEqual(item.attributeSet.title, "Hello world")
        XCTAssertEqual(item.attributeSet.thumbnailURL, URL(string: "https://lemmy.world/pic.jpg"))
    }

    func test_makeItem_returnsNilWhenNoCanonicalURL() {
        let row = IndexableContentRow(
            serverPostId: 5,
            title: "No URL",
            originalPostUrl: nil,
            thumbnailUrl: nil,
            communityName: nil
        )
        XCTAssertNil(ContentSpotlightIndexer.makeItem(from: row))
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (`ContentSpotlightIndexer` not found).

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

```swift
// Spud/Integration/ContentSpotlightIndexer.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreSpotlight
import Foundation
import OSLog
import SpudDataKit
import SpudUtilKit
import UniformTypeIdentifiers

private let logger = Logger.app

/// Indexes the default account's saved + recently-opened posts into Spotlight,
/// under a dedicated `content` domain (kept separate from the community index).
/// Each item's identifier is the canonical routing URL, so a tap funnels through
/// `SceneDelegate.scene(_:continue:)` -> `AppCoordinator.open` like any deep
/// link. Best-effort: re-run on launch and on foreground.
enum ContentSpotlightIndexer {
    static let domainIdentifier = "content"
    static let limit = 100

    static func reindex(appDatabase: AppDatabase) {
        Task {
            let rows = appDatabase.indexableContentRowsForDefaultAccountSync(limit: limit)
            let items = rows.compactMap(makeItem(from:))
            do {
                let index = CSSearchableIndex.default()
                // Reset the domain first so unsaved / aged-out items don't linger.
                try await index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
                try await index.indexSearchableItems(items)
            } catch {
                logger.error("Spotlight content indexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pure mapping from a content row to a Spotlight item. nil when no canonical
    /// URL can be built (so the item would not be routable).
    static func makeItem(from row: IndexableContentRow) -> CSSearchableItem? {
        guard let canonical = ShareURL.forPost(
            originalPostUrl: row.originalPostUrl,
            serverPostId: row.serverPostId,
            instanceActorId: nil
        ) else { return nil }
        let routingURL = SpudInternalLink.objectAtURL(url: canonical).url
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = row.title
        if let communityName = row.communityName {
            attributes.contentDescription = "!\(communityName)"
        }
        if let thumb = row.thumbnailUrl, let thumbURL = URL(string: thumb) {
            attributes.thumbnailURL = thumbURL
        }
        return CSSearchableItem(
            uniqueIdentifier: routingURL.absoluteString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }
}
```

- [ ] **Step 4: Regenerate, run test to verify it passes**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Integration/ContentSpotlightIndexer.swift SpudTests/ContentSpotlightIndexerTests.swift
git add Spud/Integration/ContentSpotlightIndexer.swift SpudTests/ContentSpotlightIndexerTests.swift
git commit -m "feat(integration): index saved+history posts into Spotlight"
```

---

### Task 15: Hook content reindex at launch + foreground

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (`applyDefaultAccount`, ~line 192)
- Modify: `Spud/App/SceneDelegate.swift` (`sceneWillEnterForeground`, ~line 74)

**Interfaces:**
- Consumes: `ContentSpotlightIndexer.reindex(appDatabase:)` (Task 14).

No unit test (best-effort fire-and-forget hooks, mirroring `CommunitySpotlightIndexer`) — verified by build + the manual Spotlight pass.

- [ ] **Step 1: Add the call in `MainWindow.applyDefaultAccount`** next to the existing community reindex:

```swift
// Keep the Spotlight community index current for this account.
CommunitySpotlightIndexer.reindex(appDatabase: appDatabase)
// Keep the Spotlight saved + history content index current too.
ContentSpotlightIndexer.reindex(appDatabase: appDatabase)
```

- [ ] **Step 2: Add the call in `SceneDelegate.sceneWillEnterForeground`** next to the existing community reindex:

```swift
CommunitySpotlightIndexer.reindex(appDatabase: AppCoordinator.shared.dependencies.appDatabase)
ContentSpotlightIndexer.reindex(appDatabase: AppCoordinator.shared.dependencies.appDatabase)
```

Note: per-save immediacy is intentionally out of scope — saved/unsaved changes are reflected on the next foreground or launch reindex (mirrors how `CommunitySpotlightIndexer` reflects subscription changes). Flag this in the branch summary.

- [ ] **Step 3: Build to verify it compiles**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/MainWindow/MainWindow.swift Spud/App/SceneDelegate.swift
git add Spud/Scenes/MainWindow/MainWindow.swift Spud/App/SceneDelegate.swift
git commit -m "feat(integration): reindex saved+history Spotlight on launch and foreground"
```

- [ ] **Step 5: Full test pass + manual Spotlight/Handoff verification**

Run the full app + data-layer suites:
`python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17" --test --suite SpudTests` and `--test --suite SpudDataKit`.
Manual: a saved post and a viewed post both appear in Spotlight and open to the right screen; Open Saved + Switch Account appear in Shortcuts; Siri phrases work; Handoff a post phone→iPad. Also build the widget scheme to confirm app-only code didn't leak into it: `--scheme SpudWidgetExtension`.

---

## Self-Review

**Spec coverage:**
- Slice 1 (NSUserActivity/Handoff): Task 1 (factory+decoder), Tasks 2/3/5 (vend on post/community/person), Task 4 (person actorId read), Task 6 (continuation + Info.plist). ✓
- Slice 2 (App Intents completion): Task 7 (savedFeed routing), Task 8 (Open Saved), Tasks 9/10/11 (accountsSync → AccountAppEntity/query → Switch Account), Task 12 (community donation). ✓
- Slice 3 (Spotlight content): Task 13 (queries), Task 14 (indexer), Task 15 (hooks + taps via Slice 1). ✓
- Decided routing key (`.objectAtURL` ap_id / `.community`): used in Tasks 2/3/5/14. ✓
- One `scene(_:continue:)` backbone for both Handoff + Spotlight: Task 6. ✓
- AppIntents extension deferred: not built (in-app target only). ✓

**Spec correction baked in:** `isSaved` is on `PostRecord`, not `postInteraction` — Task 13's query joins `post` for both the saved filter and the canonical `ap_id` (verified against `observeHistoryRows`).

**Open-risk dispositions:**
- `ShareURL.forPost` reuse: confirmed reusable as-is (Task 2 passes the same inputs as `sharePost`).
- `IntentDonationManager.donate` signature: Task 12 Step 1 verifies via apple-docs before coding.
- `CSSearchableItem` thumbnail: Task 14 sets `thumbnailURL` (remote) and skips when absent.
- `postInteraction.isSaved` semantics: corrected — saved state read from `post.isSaved` (the Follow=Save unification lives there).
- `scene(_:continue:)` + pending nav: reuses `AppCoordinator.open` (URL path); cold launch handled by `willConnectTo` creating the window before routing, so no new pending mechanism is introduced.

**Placeholder scan:** No TBD/TODO; every code step has complete code. Two flagged verification sub-steps (Task 2 Step 2 header-title property name; Task 12 Step 1 donate signature) are concrete checks, not deferred work.

**Type consistency:** `IndexableContentRow` fields are identical in Tasks 13/14. `AccountAppEntity(id/nickname/instanceHost)` identical in Tasks 10/11 and the test. `selectSavedFeed(sort:)` / `.savedFeed(sort:)` consistent across Tasks 7/8. `routingURL(from:)` / `viewPost(routingURL:title:)` consistent across Tasks 1/2/6.

## Notes for execution

- **Worktree:** create a direct sibling off current `main` — `git worktree add -b feat/handoff-spotlight-intents ../Spud-handoff-spotlight main` (NOT under `.claude/worktrees/`; `../LemmyKit` must resolve). Copy this plan + the spec into the worktree and remove the untracked originals from the main checkout to avoid a later merge collision. Teardown: `rm -rf ../Spud-handoff-spotlight && git worktree prune && git branch -d feat/handoff-spotlight-intents`.
- **`main` is being churned by another agent** — re-check `git log -1 main` before the final merge; merge `--no-ff`; do NOT push.
- Run `make project` whenever a task adds a new file before its build/test step (already inlined in those tasks).
