# Blur NSFW Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `blur_nsfw` preference (default on) that obscures shown NSFW media behind a tap-to-reveal overlay, surfaced in app settings and the Quick Switch filter, plus coherent NSFW handling (discovery gating, shared badge, age acknowledgment).

**Architecture:** A new client preference mirrors the existing one-directional `show_nsfw` sync (local `@UserDefaultsBacked` source of truth → pushed to the server on the frontpage feed only). The client gains a `post.isNsfw` column (it never recorded NSFW before, since filtering was purely server-side). Rendering uses a reusable `UIVisualEffectView` overlay with session-only per-post reveal; no Core Image processing. Blur is independent of show/hide and only takes visible effect when NSFW is shown.

**Tech Stack:** UIKit + SwiftUI (settings/Quick Switch), GRDB (SQLite), LemmyKit (remote-pinned 0.5.0), swift-snapshot-testing, XCTest.

## Global Constraints

- **No LemmyKit change.** Pinned LemmyKit 0.5.0 already exposes `saveUserSettings(blurNSFW: Bool? = nil)` and `local_user.blur_nsfw`. Do not edit `../LemmyKit`.
- **Migration is the next case only:** `v20_postNsfw`. `v19_favoritedCommunity` is taken. Never edit an existing migration.
- **Defaults:** blur is **ON** (`true`); show is **OFF** (`false`, unchanged).
- **No emojis** in code, comments, docs, or commit messages.
- **SwiftFormat is authoritative.** Run `mint run swiftformat <paths>` before staging (pre-commit hook lints only).
- **Swift 6 language mode** for shipped targets and `SpudDataKitTests`; snapshot/UI test targets stay Swift 5.
- **Snapshot tests** run under the `SpudSnapshots` test plan; newer screen snapshots pin `.image(on:traits:)` so any sim records them. First run records refs + fails; rerun verifies. git-annex stores refs — record/verify one class at a time, `git add` the PNGs after a green verify, never `git annex restage` between record and verify.
- **Git:** work on a feature branch (`feat/blur-nsfw`) or worktree, not directly on `main`. Stage explicit paths (`git status -uall` to see untracked — plain status hides them here). Never `git add -A`; never touch `.remember/` or `/worktrees/` paths.
- **Build/test commands** (from `Spud/`):
  - Unit (SpudDataKit): `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
  - Build: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
  - Snapshots (one class): `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/<Class> -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
- After adding/removing source files, run `make project` (XcodeGen) before building.

## Testing posture (read before starting)

This repo's real automated coverage is **SpudDataKitTests** (rich fakes + `AppDatabase.inMemory()`) and **snapshot tests**. The app-target view/preference layer is verified by **build + snapshot + on-device**, matching how the existing `show_nsfw` toggle is covered (it has no unit tests). Tasks therefore use:
- **Full TDD** (failing test → impl → pass) for data, importer, sync, and observation logic → SpudDataKitTests.
- **Snapshot tests** for rendering.
- **Build-verified + explicit manual check** for pure UI wiring (toggles, observers, age-ack), with the manual steps written out.

## File structure

| File | Responsibility | Action |
|---|---|---|
| `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` | add `v20_postNsfw` | modify |
| `SpudDataKit/Services/AppDatabase/Records/Post.swift` | `PostRecord.isNsfw` | modify |
| `SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift` | map `post.nsfw` | modify |
| `SpudDataKit/Services/AppDatabase/PostListObservations.swift` | `PostListRow.isNsfw` (post OR community) | modify |
| `SpudDataKit/Services/AppDatabase/Records/Account.swift` | `AccountRecord.blurNsfw` cache | modify |
| `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift` | map `blur_nsfw`; `setAccountBlurNsfw` | modify |
| `SpudDataKit/Services/Lemmy/LemmyService.swift` | `setBlurNsfw` (protocol + impl) | modify |
| `Spud/Services/Preferences/PreferencesService.swift` | `blurNsfw` + `hasAcknowledgedNsfwAge` | modify |
| `Spud/Scenes/Preferences/PreferencesViewModel.swift` | `blurNsfw` + `updateBlurNsfw` | modify |
| `Spud/Scenes/Preferences/PreferencesPostMarkingAndHidingView.swift` | Blur toggle (disabled when show off) | modify |
| `Spud/Scenes/PostList/QuickSwitch/QuickSwitchViewModel.swift` | `blurNsfw` + `updateBlurNsfw` | modify |
| `Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift` | Blur toggle (disabled when show off) | modify |
| `Spud/Scenes/PostList/PostListViewController.swift` | observe `blurNsfwStream`; frontpage server sync; reveal set | modify |
| `Spud/Scenes/Shared/NsfwBlurOverlayView.swift` | reusable blur+reveal overlay | create |
| `Spud/Scenes/PostList/PostListThumbnailImageView.swift` | host the overlay | modify |
| `Spud/Scenes/PostList/PostListPostCell.swift` | wire isNsfw + blur pref + reveal | modify |
| `Spud/Scenes/PostList/PostListPostViewModel.swift` | carry `isNsfw`, `blurNsfw`, `isRevealed` | modify |
| `Spud/Scenes/PostDetail/PostDetailHeaderCell.swift` | header image blur | modify |
| `SpudUIKit/.../NsfwBadge.swift` (or shared SwiftUI) | one NSFW pill | create |
| `Spud/Scenes/Discover/DiscoverView.swift` | use shared badge | modify |
| `Spud/Scenes/Discover/CommunityIcon.swift` | blur NSFW community icon | modify |
| `Spud/Scenes/Community/Content/CommunityHeaderView.swift` | blur NSFW community art + badge | modify |
| `Spud/Scenes/Search/SearchResults.swift` | NSFW filter helper | modify |
| `Spud/Scenes/Search/SearchViewModel.swift` | apply gating when show off | modify |
| `Spud/Scenes/Composer/CommunityPickerViewController.swift` | apply gating when show off | modify |
| `SpudDataKitTests/Fakes/Post+fake.swift` | `nsfw` param | modify |
| `SpudDataKitTests/Fakes/Community+fake.swift` | `nsfw` param | modify |
| `docs/features/nsfw-content.md`, `docs/features/README.md` | docs | modify |

---

### Task 1: Record that a post is NSFW (migration + record + importer)

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (after the `v19_favoritedCommunity` block, before `return migrator`)
- Modify: `SpudDataKit/Services/AppDatabase/Records/Post.swift`
- Modify: `SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift:158-200` (the `apply(view:to:now:)` method)
- Modify (test fake): `SpudDataKitTests/Fakes/Post+fake.swift`
- Test: `SpudDataKitTests/PostNsfwImportTests.swift` (create)

**Interfaces:**
- Produces: `PostRecord.isNsfw: Bool` (default `false`); the `post` table column `isNsfw`.

- [ ] **Step 1: Add an `nsfw` parameter to the Post fake** so tests can build NSFW posts.

In `SpudDataKitTests/Fakes/Post+fake.swift`, change the signature and the `nsfw:` line:

```swift
extension Components.Schemas.Post {
    static func fake(
        creator: Components.Schemas.Person,
        community: Components.Schemas.Community,
        nsfw: Bool = false
    ) -> Components.Schemas.Post {
        .init(
            id: 1,
            name: "Hello world",
            url: nil,
            body: "Hello example world",
            creator_id: creator.id,
            community_id: community.id,
            removed: false,
            locked: false,
            published: Date(timeIntervalSince1970: 1_685_577_784),
            updated: nil,
            deleted: false,
            nsfw: nsfw,
            embed_title: nil,
            embed_description: nil,
            thumbnail_url: nil,
            ap_id: "https://example.com/post/1",
            local: true,
            embed_video_url: nil,
            language_id: 1,
            featured_community: false,
            featured_local: false
        )
    }
}
```

- [ ] **Step 2: Write the failing test**

Create `SpudDataKitTests/PostNsfwImportTests.swift`. Model the setup on `LemmyServiceFetchPersistenceTests` (uses `AppDatabase.inMemory()` + the `*+fake` builders). Adjust the upsert entry point / account+site seeding to match that file's helpers.

```swift
import XCTest
import LemmyKit
@testable import SpudDataKit

final class PostNsfwImportTests: XCTestCase {
    func test_upsertPost_persistsNsfwFlagFromPostView() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await appDatabase.seedAccountAndSite() // see note below

        let person = Components.Schemas.Person.fake()
        let community = Components.Schemas.Community.fake()
        let post = Components.Schemas.Post.fake(creator: person, community: community, nsfw: true)
        let view = Components.Schemas.PostView.fake(post: post, creator: person, community: community)

        let rowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, in: db)
        }

        let record = try await appDatabase.writer.read { db in
            try PostRecord.filter(key: rowId).fetchOne(db)
        }
        XCTAssertEqual(record?.isNsfw, true)
    }
}
```

Note: replace `seedAccountAndSite()` with whatever the sibling persistence tests use to create an account row + site row (copy that helper or its inline setup). `Person.fake()` / `Community.fake()` parameter shapes follow the existing fakes.

- [ ] **Step 3: Run the test to verify it fails**

Run the SpudDataKitTests command (Global Constraints). Expected: FAIL — `PostRecord` has no `isNsfw` member (compile error) or the value is absent.

- [ ] **Step 4: Add the column to the migration**

In `AppDatabase+Migrations.swift`, immediately after the closing brace of the `v19_favoritedCommunity` registration and before `return migrator`:

```swift
        migrator.registerMigration("v20_postNsfw") { db in
            // The client treated NSFW as purely server-filtered, so it never
            // recorded whether a post was NSFW. Blur-on-display needs that flag.
            try db.alter(table: "post") { t in
                t.add(column: "isNsfw", .boolean).notNull().defaults(to: false)
            }
        }
```

- [ ] **Step 5: Add the stored property to `PostRecord`**

In `Records/Post.swift`, add the property (place it next to the other moderation/content flags, e.g. after `isHidden`), the matching `init` parameter (default `false`), and the assignment in `init`:

```swift
    /// Whether the post is marked not-safe-for-work (`PostView.post.nsfw`).
    /// Drives blur-on-display; the client did not record this before blur.
    public var isNsfw: Bool
```

Add to the initializer parameter list (after `isHidden: Bool = false,`):

```swift
        isNsfw: Bool = false,
```

Add to the initializer body (after `self.isHidden = isHidden`):

```swift
        self.isNsfw = isNsfw
```

- [ ] **Step 6: Map it in the importer**

In `PostImporter.swift`, inside `apply(view:to:now:)`, next to the other `record.isXxx = post.xxx` moderation lines (after `record.isDeleted = post.deleted`):

```swift
        record.isNsfw = post.nsfw
```

- [ ] **Step 7: Run the test to verify it passes**

Run the SpudDataKitTests command. Expected: PASS.

- [ ] **Step 8: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase SpudDataKitTests/PostNsfwImportTests.swift SpudDataKitTests/Fakes/Post+fake.swift
git add SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKit/Services/AppDatabase/Records/Post.swift SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift SpudDataKitTests/PostNsfwImportTests.swift SpudDataKitTests/Fakes/Post+fake.swift
git commit -m "feat: record post NSFW flag (v20 migration)"
```

---

### Task 2: Expose `isNsfw` on `PostListRow` (post OR community)

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/PostListObservations.swift` (struct `PostListRow`, its `init`, the SELECT, and the row-mapping closure)
- Modify (test fake): `SpudDataKitTests/Fakes/Community+fake.swift` (add `nsfw` param if absent)
- Test: `SpudDataKitTests/PostListRowNsfwTests.swift` (create)

**Interfaces:**
- Consumes: `post.isNsfw` (Task 1), `community.isNsfw` (existing column).
- Produces: `PostListRow.isNsfw: Bool` — true when the post OR its community is NSFW.

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/PostListRowNsfwTests.swift`. Seed two posts into a feed (one with `post.nsfw = true` in an SFW community, one SFW post in an NSFW community) and assert both rows report `isNsfw == true`, and a fully-SFW post reports `false`. Model feed seeding on `HistoryObservationsTests` / `LemmyServiceFetchFeedPersistenceTests`.

```swift
import XCTest
import LemmyKit
@testable import SpudDataKit

final class PostListRowNsfwTests: XCTestCase {
    func test_postListRow_isNsfw_trueWhenPostOrCommunityNsfw() async throws {
        let appDatabase = try AppDatabase.inMemory()
        // Seed a feed with three posts: (a) post.nsfw, (b) community.nsfw,
        // (c) neither. Reuse the feed-seeding helper from the sibling feed tests.
        let rows = try await appDatabase.seedFeedRowsForNsfwTest() // see note
        XCTAssertEqual(rows.first { $0.title == "nsfw-post" }?.isNsfw, true)
        XCTAssertEqual(rows.first { $0.title == "nsfw-community" }?.isNsfw, true)
        XCTAssertEqual(rows.first { $0.title == "clean" }?.isNsfw, false)
    }
}
```

Note: `seedFeedRowsForNsfwTest()` stands in for inline seeding — build three `PostView`s with `Post.fake(..., nsfw:)` and `Community.fake(..., nsfw:)`, upsert them into a feed page, then read `observePostListRows(feedId:)`'s first emission. Copy the page/feed seeding from the sibling feed-persistence test.

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `PostListRow` has no `isNsfw`.

- [ ] **Step 3: Add `isNsfw` to the struct + init**

In `PostListObservations.swift`, add to the `PostListRow` stored properties (after `isDeleted`):

```swift
    /// Whether the post or its community is marked NSFW. Drives blur-on-display.
    public let isNsfw: Bool
```

Add the `init` parameter (after `isDeleted: Bool,`):

```swift
        isNsfw: Bool,
```

Add the assignment (after `self.isDeleted = isDeleted`):

```swift
        self.isNsfw = isNsfw
```

- [ ] **Step 4: Select it in the SQL**

In the SELECT inside `observePostListRows`, add a computed column after `post.isDeleted   AS isDeleted,`:

```sql
                            (post.isNsfw OR community.isNsfw) AS isNsfw,
```

- [ ] **Step 5: Map it in the row closure**

In the `PostListRow(...)` construction inside `rows.compactMap`, add (after `isDeleted: row["isDeleted"],`):

```swift
                        isNsfw: row["isNsfw"],
```

- [ ] **Step 6: Run to verify it passes**

Expected: PASS.

- [ ] **Step 7: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/PostListObservations.swift SpudDataKitTests/PostListRowNsfwTests.swift
git add SpudDataKit/Services/AppDatabase/PostListObservations.swift SpudDataKitTests/PostListRowNsfwTests.swift SpudDataKitTests/Fakes/Community+fake.swift
git commit -m "feat: expose isNsfw on PostListRow (post or community)"
```

---

### Task 3: `blurNsfw` preference (service + protocol)

**Files:**
- Modify: `Spud/Services/Preferences/PreferencesService.swift` (protocol block ~lines 91-100; concrete block ~lines 271-276)

**Interfaces:**
- Produces: `PreferencesServiceType.blurNsfw: Bool { get set }` and `blurNsfwStream: AsyncStream<Bool> { get }`. Default `true`.

This mirrors `showNsfw` exactly (already shipped, no unit test of its own). Behavior is exercised by the view-model tasks; this task is verified by build.

- [ ] **Step 1: Add to the protocol**

In `PreferencesService.swift`, after the `showNsfwStream` protocol members (line ~100):

```swift
    var blurNsfw: Bool { get set }
    var blurNsfwStream: AsyncStream<Bool> { get }
```

- [ ] **Step 2: Add to the concrete service**

After the concrete `showNsfwStream` (line ~276):

```swift
    @UserDefaultsBacked(key: "blurNsfw")
    var blurNsfw: Bool = true

    var blurNsfwStream: AsyncStream<Bool> {
        $blurNsfw
    }
```

- [ ] **Step 3: Build to verify**

Run the build command. Expected: builds clean (any in-target fake conforming to `PreferencesServiceType` will fail to compile until Task 6/7 — if a test fake exists, add the two members there too; search `: PreferencesServiceType` to find conformances).

- [ ] **Step 4: Format + commit**

```bash
mint run swiftformat Spud/Services/Preferences/PreferencesService.swift
git add Spud/Services/Preferences/PreferencesService.swift
git commit -m "feat: add blurNsfw preference (default on)"
```

---

### Task 4: Account-row cache + importer for `blur_nsfw`

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Records/Account.swift`
- Modify: `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift` (`apply(myUser:...)` ~line 417; add `setAccountBlurNsfw` next to `setAccountShowNsfw` ~line 159)
- Test: `SpudDataKitTests/AccountBlurNsfwTests.swift` (create)

**Interfaces:**
- Produces: `AccountRecord.blurNsfw: Bool?`; `AppDatabase.setAccountBlurNsfw(_:forKeychainId:)`.

Note: `AccountRecord.blurNsfw` is a **non-persisted-by-migration** column only if the `account` table is created with all `AccountRecord` fields. Check `AppDatabase+Migrations.swift` for the `account` table definition — if it lists explicit columns, add `blurNsfw` via a column add in the **same `v20_postNsfw`** migration (a migration may alter multiple tables). If the account table is created generically, no DDL is needed. Verify before Step 4.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import SpudDataKit

final class AccountBlurNsfwTests: XCTestCase {
    func test_setAccountBlurNsfw_mirrorsOntoAccountRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = try await appDatabase.seedSignedInAccount() // copy from AccountQueriesTests
        try await appDatabase.setAccountBlurNsfw(false, forKeychainId: keychainId)
        let account = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == keychainId).fetchOne(db)
        }
        XCTAssertEqual(account?.blurNsfw, false)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — no `blurNsfw` / no `setAccountBlurNsfw`.

- [ ] **Step 3: Add `blurNsfw` to `AccountRecord`**

In `Records/Account.swift`, add the property after `showNsfw`:

```swift
    public var blurNsfw: Bool?
```

Add the init parameter after `showNsfw: Bool? = nil,`:

```swift
        blurNsfw: Bool? = nil,
```

Add the assignment after `self.showNsfw = showNsfw`:

```swift
        self.blurNsfw = blurNsfw
```

- [ ] **Step 4: (If needed) add the account column to the v20 migration**

Only if the `account` table is created with explicit columns (see the note above). In the `v20_postNsfw` migration block, add a second alter:

```swift
            try db.alter(table: "account") { t in
                t.add(column: "blurNsfw", .boolean)
            }
```

- [ ] **Step 5: Map it from the server on import**

In `AccountImporter.swift`, in `apply(myUser:...)`, after `record.showNsfw = local.show_nsfw`:

```swift
        record.blurNsfw = local.blur_nsfw
```

- [ ] **Step 6: Add the mirror helper**

In `AccountImporter.swift`, directly after `setAccountShowNsfw(_:forKeychainId:)`:

```swift
    /// Mirrors the `local_user.blur_nsfw` setting onto the account row matching
    /// `keychainId`, so the locally-cached value stays in sync after the app
    /// pushes a change to the server. No-op if the row hasn't been imported yet.
    func setAccountBlurNsfw(_ blurNsfw: Bool, forKeychainId keychainId: String) async throws {
        try await writer.write { db in
            guard var account = try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchOne(db)
            else { return }
            account.blurNsfw = blurNsfw
            account.updatedAt = Date()
            try account.update(db)
        }
    }
```

- [ ] **Step 7: Run to verify it passes**

Expected: PASS.

- [ ] **Step 8: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase SpudDataKitTests/AccountBlurNsfwTests.swift
git add SpudDataKit/Services/AppDatabase/Records/Account.swift SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift SpudDataKitTests/AccountBlurNsfwTests.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift
git commit -m "feat: cache + import account blur_nsfw setting"
```

---

### Task 5: `LemmyService.setBlurNsfw` (push to server + mirror)

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (protocol decl ~line 52; impl after `setShowNsfw` ~line 866)
- Test: `SpudDataKitTests/LemmyServiceBlurNsfwTests.swift` (create)

**Interfaces:**
- Consumes: `api.saveUserSettings(blurNSFW:)`, `appDatabase.setAccountBlurNsfw(_:forKeychainId:)` (Task 4).
- Produces: `LemmyServiceType.setBlurNsfw(_ blurNsfw: Bool) async throws`.

This is a near-verbatim clone of `setShowNsfw` (LemmyService.swift:828-866). Model the test on `LemmyServiceSaveTests` / `LemmyServiceModerationTests`, which use the fake api and assert the call was made.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import LemmyKit
@testable import SpudDataKit

final class LemmyServiceBlurNsfwTests: XCTestCase {
    func test_setBlurNsfw_signedIn_callsSaveUserSettingsAndMirrors() async throws {
        // Arrange a signed-in LemmyService with a fake api (copy harness from
        // LemmyServiceSaveTests: in-memory db, seeded signed-in account, FakeApi).
        let harness = try await LemmyServiceTestHarness.signedIn()
        try await harness.service.setBlurNsfw(false)
        XCTAssertEqual(harness.fakeApi.lastSaveUserSettings?.blurNSFW, false)
        let account = try await harness.appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == harness.keychainId).fetchOne(db)
        }
        XCTAssertEqual(account?.blurNsfw, false)
    }

    func test_setBlurNsfw_signedOut_isNoOp() async throws {
        let harness = try await LemmyServiceTestHarness.signedOut()
        try await harness.service.setBlurNsfw(false)
        XCTAssertNil(harness.fakeApi.lastSaveUserSettings)
    }
}
```

Note: adapt `LemmyServiceTestHarness` and `fakeApi.lastSaveUserSettings` to the actual fake-api capture mechanism used by the sibling LemmyService tests (find how they assert `saveUserSettings` / other api calls; the fake likely records the last call). If the fake doesn't yet capture `saveUserSettings`, extend it minimally to record `blurNSFW`.

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `setBlurNsfw` does not exist.

- [ ] **Step 3: Declare it in the protocol**

In `LemmyService.swift`, after the `setShowNsfw` protocol declaration (~line 56), add:

```swift
    /// Push the account's `blur_nsfw` preference to the server via
    /// `saveUserSettings`, then mirror the new value onto the local account
    /// row so the cached `AccountRecord.blurNsfw` stays in sync. Requires a
    /// signed-in account: a signed-out account is a silent no-op (blur is a
    /// pure client-side render concern there).
    func setBlurNsfw(_ blurNsfw: Bool) async throws
```

- [ ] **Step 4: Implement it**

After the `setShowNsfw(_:)` implementation (~line 866), add the clone:

```swift
    public func setBlurNsfw(_ blurNsfw: Bool) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Set blur_nsfw skipped - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            return
        }

        logger.debug("""
            Set blur_nsfw=\(blurNsfw, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
            """)

        do {
            _ = try await api.saveUserSettings(blurNSFW: blurNsfw)
        } catch {
            logger.error("""
                Set blur_nsfw failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        do {
            try await appDatabase.setAccountBlurNsfw(
                blurNsfw,
                forKeychainId: accountIdentifierForLogging
            )
        } catch {
            logger.error("""
                Mirror blur_nsfw to AppDatabase failed. \(String(describing: error), privacy: .public)
                """)
        }
    }
```

- [ ] **Step 5: Run to verify it passes**

Expected: PASS.

- [ ] **Step 6: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKitTests/LemmyServiceBlurNsfwTests.swift
git add SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKitTests/LemmyServiceBlurNsfwTests.swift
git commit -m "feat: LemmyService.setBlurNsfw (server sync + mirror)"
```

---

### Task 6: Settings toggle (PreferencesViewModel + view)

**Files:**
- Modify: `Spud/Scenes/Preferences/PreferencesViewModel.swift` (property ~line 118; seed ~line 195; stream obs ~line 302; method ~line 545)
- Modify: `Spud/Scenes/Preferences/PreferencesPostMarkingAndHidingView.swift`

**Interfaces:**
- Consumes: `PreferencesService.blurNsfw` / `blurNsfwStream` (Task 3).
- Produces: `PreferencesViewModel.blurNsfw`, `updateBlurNsfw(_:)`.

- [ ] **Step 1: Add the property** (after `var showNsfw: Bool` ~line 118):

```swift
    var blurNsfw: Bool
```

- [ ] **Step 2: Seed it** (after `showNsfw = dependencies.preferencesService.showNsfw` ~line 195):

```swift
        blurNsfw = dependencies.preferencesService.blurNsfw
```

- [ ] **Step 3: Observe the stream** (after the `showNsfwStream` observation block ~line 306):

```swift
        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.blurNsfwStream {
                self?.blurNsfw = value
            }
        })
```

- [ ] **Step 4: Add the update method** (after `updateShowNsfw` ~line 554):

```swift
    func updateBlurNsfw(_ value: Bool) {
        guard value != blurNsfw else { return }
        blurNsfw = value
        // Local write is enough: post lists / post detail observe
        // `blurNsfwStream` and re-apply blur in place, and the frontpage list
        // mirrors the value to the server for signed-in accounts.
        preferencesService?.blurNsfw = value
        Haptics.tap()
    }
```

- [ ] **Step 5: Add the toggle to the view**

In `PreferencesPostMarkingAndHidingView.swift`, add a binding (after the `showNsfw` binding):

```swift
    private var blurNsfw: Binding<Bool> {
        .init { viewModel.blurNsfw } set: { viewModel.updateBlurNsfw($0) }
    }
```

Replace the NSFW `Section` body to add the Blur row beneath Show, disabled when Show is off:

```swift
            Section {
                Toggle(isOn: showNsfw) {
                    Label(
                        NSLocalizedString("Show NSFW Content", comment: "Settings toggle: show not-safe-for-work content"),
                        systemImage: viewModel.showNsfw ? "eye" : "eye.slash"
                    )
                }
                Toggle(isOn: blurNsfw) {
                    Label(
                        NSLocalizedString("Blur NSFW Content", comment: "Settings toggle: blur not-safe-for-work media"),
                        systemImage: "drop.fill"
                    )
                }
                .disabled(!viewModel.showNsfw)
            } header: {
                Text("NSFW")
            } footer: {
                if viewModel.showNsfw {
                    Text("Blur media in posts and communities marked not-safe-for-work until you tap to reveal.")
                } else {
                    Text("Show posts and communities marked not-safe-for-work. Blur only applies when NSFW content is shown.")
                }
            }
```

- [ ] **Step 6: Build to verify** (Spud scheme). Expected: builds clean.

- [ ] **Step 7: Manual check**

Launch app → Settings → Post Marking & Hiding. With Show NSFW off, the Blur row is greyed. Turn Show on → Blur becomes enabled, defaults on.

- [ ] **Step 8: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Preferences
git add Spud/Scenes/Preferences/PreferencesViewModel.swift Spud/Scenes/Preferences/PreferencesPostMarkingAndHidingView.swift
git commit -m "feat: Blur NSFW toggle in settings"
```

---

### Task 7: Quick Switch toggle (the post-list config filter)

**Files:**
- Modify: `Spud/Scenes/PostList/QuickSwitch/QuickSwitchViewModel.swift`
- Modify: `Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift`

**Interfaces:**
- Consumes: `PreferencesService.blurNsfw` (Task 3).
- Produces: `QuickSwitchViewModel.blurNsfw`, `updateBlurNsfw(_:)`.

- [ ] **Step 1: Add property + seed** in `QuickSwitchViewModel.swift` — add `var blurNsfw: Bool` after `var showNsfw: Bool`, and in `init` after `showNsfw = preferencesService.showNsfw`:

```swift
        blurNsfw = preferencesService.blurNsfw
```

- [ ] **Step 2: Add the update method** (after `updateShowNsfw`):

```swift
    /// Writes the blur preference through `PreferencesService`. The hosting
    /// `PostListViewController` observes `blurNsfwStream`, so toggling here
    /// re-applies blur in place (and syncs to the server on the frontpage).
    func updateBlurNsfw(_ value: Bool) {
        blurNsfw = value
        preferencesService.blurNsfw = value
        Haptics.tap()
    }
```

- [ ] **Step 3: Add the toggle to the view** in `QuickSwitchView.swift` — add a binding after `showNsfw`:

```swift
    private var blurNsfw: Binding<Bool> {
        .init { viewModel.blurNsfw } set: { viewModel.updateBlurNsfw($0) }
    }
```

Replace the Show NSFW `Section` to add the Blur row beneath, disabled when Show is off:

```swift
                Section {
                    Toggle(isOn: showNsfw) {
                        Label("Show NSFW", systemImage: viewModel.showNsfw ? "eye" : "eye.slash")
                    }
                    Toggle(isOn: blurNsfw) {
                        Label("Blur NSFW", systemImage: "drop.fill")
                    }
                    .disabled(!viewModel.showNsfw)
                } footer: {
                    Text(viewModel.showNsfw
                        ? "Blur NSFW media until you tap to reveal."
                        : "Show posts marked not-safe-for-work.")
                }
```

- [ ] **Step 4: Build + manual check.** Open a feed → Quick Switch popover → confirm Blur row appears under Show, greyed when Show is off.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Scenes/PostList/QuickSwitch
git add Spud/Scenes/PostList/QuickSwitch/QuickSwitchViewModel.swift Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift
git commit -m "feat: Blur NSFW toggle in Quick Switch"
```

---

### Task 8: `NsfwBlurOverlayView` (reusable component)

**Files:**
- Create: `Spud/Scenes/Shared/NsfwBlurOverlayView.swift`
- Run `make project` after creating (new source file).

**Interfaces:**
- Produces: `final class NsfwBlurOverlayView: UIView` with `var onReveal: (() -> Void)?` and `func setRevealed(_ revealed: Bool)`. When not revealed, it shows an opaque blur material + an `eye.slash` glyph + caption; tapping calls `onReveal`. Hidden entirely when revealed.

- [ ] **Step 1: Create the component**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A tap-to-reveal blur layer placed over NSFW media. Add it as a subview
/// pinned to the host image view's edges. While not revealed it covers the
/// image with a blur material and an "eye.slash" hint; tapping calls
/// ``onReveal``. Reveal state is owned by the host (session-only), so the host
/// calls ``setRevealed(_:)`` on configure and reuse.
final class NsfwBlurOverlayView: UIView {
    /// Called when the user taps the overlay to reveal the media.
    var onReveal: (() -> Void)?

    /// Whether a caption ("Tap to reveal") is shown. Off for tight thumbnails.
    var showsCaption: Bool {
        get { !captionLabel.isHidden }
        set { captionLabel.isHidden = !newValue }
    }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))

    private lazy var glyphView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "eye.slash.fill", withConfiguration: config))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .secondaryLabel
        return view
    }()

    private lazy var captionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("Tap to reveal", comment: "NSFW blur overlay hint")
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        let stack = UIStackView(arrangedSubviews: [glyphView, captionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        blurView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))

        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("NSFW content, hidden", comment: "NSFW blur overlay accessibility label")
        accessibilityTraits = .button
        accessibilityHint = NSLocalizedString("Double tap to reveal", comment: "NSFW blur overlay accessibility hint")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func didTap() { onReveal?() }

    /// Shows or hides the overlay. When revealed the overlay is hidden and
    /// pass-through (so taps reach the underlying media).
    func setRevealed(_ revealed: Bool) {
        isHidden = revealed
    }
}
```

- [ ] **Step 2: `make project` + build.** Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
mint run swiftformat Spud/Scenes/Shared/NsfwBlurOverlayView.swift
git add Spud/Scenes/Shared/NsfwBlurOverlayView.swift
git commit -m "feat: NsfwBlurOverlayView tap-to-reveal component"
```

---

### Task 9: Blur NSFW thumbnails in the post list

**Files:**
- Modify: `Spud/Scenes/PostList/PostListThumbnailImageView.swift` (host the overlay)
- Modify: `Spud/Scenes/PostList/PostListPostViewModel.swift` (carry `isNsfw`, `blurNsfw`, `isRevealed`)
- Modify: `Spud/Scenes/PostList/PostListPostCell.swift` (`configure(with:imageService:)` line ~404; `thumbnailTapped` line ~310; `prepareForReuse`)
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (reveal set; cellProvider line ~1055; blur-stream observer + reconfigure)
- Test: `SpudSnapshotTests/PostListNsfwBlurSnapshotTests.swift` (create)

**Interfaces:**
- Consumes: `PostListRow.isNsfw` (Task 2), `PreferencesService.blurNsfw` (Task 3), `NsfwBlurOverlayView` (Task 8).
- Produces: `PostListThumbnailImageView.isBlurred: Bool` + `onRevealBlur: (() -> Void)?`; `PostListPostViewModel.isNsfw/blurNsfw/isRevealed`.

- [ ] **Step 1: Add overlay support to the thumbnail view**

In `PostListThumbnailImageView.swift`, add a lazy `blurOverlay`, add it as a subview pinned to all edges in `init`, and expose control:

```swift
    /// Tap-to-reveal NSFW overlay, hidden unless `isBlurred` is set.
    private lazy var blurOverlay: NsfwBlurOverlayView = {
        let overlay = NsfwBlurOverlayView()
        overlay.showsCaption = false // 64pt square: glyph only
        overlay.isHidden = true
        overlay.onReveal = { [weak self] in self?.onRevealBlur?() }
        return overlay
    }()

    /// Called when the user taps the blur overlay to reveal the thumbnail.
    var onRevealBlur: (() -> Void)?

    /// Whether to cover the thumbnail with the NSFW blur overlay.
    var isBlurred: Bool = false {
        didSet { blurOverlay.setRevealed(!isBlurred) }
    }
```

In `init`, after `addSubview(playIconView)`:

```swift
        addSubview(blurOverlay)
```

and add to the `NSLayoutConstraint.activate([...])` list:

```swift
            blurOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurOverlay.topAnchor.constraint(equalTo: topAnchor),
            blurOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
```

In `prepareForReuse()`, add:

```swift
        isBlurred = false
        onRevealBlur = nil
```

- [ ] **Step 2: Carry NSFW state on the cell view model**

In `PostListPostViewModel.swift`, add stored values for `isNsfw`, `blurNsfw`, and `isRevealed` (follow how the view model already maps from `PostListRow` + preferences; the row provides `isNsfw`, the controller provides `blurNsfw` from preferences and `isRevealed` from its reveal set). Effective blur = `isNsfw && blurNsfw && !isRevealed`. Expose a computed `var isThumbnailBlurred: Bool { isNsfw && blurNsfw && !isRevealed }`.

- [ ] **Step 3: Wire it in `configure`**

In `PostListPostCell.configure(with:imageService:)`, after the thumbnail is configured, set:

```swift
        thumbnailView.isBlurred = viewModel.isThumbnailBlurred
        thumbnailView.onRevealBlur = { [weak self] in self?.revealNsfwTapped?() }
```

Add a `var revealNsfwTapped: (() -> Void)?` callback property to the cell (reset to nil in `prepareForReuse`, alongside the other `imageTapped = nil` resets).

- [ ] **Step 4: Own the reveal set in the controller**

In `PostListViewController.swift`, add a session-only set:

```swift
    /// Posts whose NSFW media the user revealed this session (by row id).
    /// Not persisted; resets on relaunch.
    private var revealedNsfwPostIds: Set<Int64> = []
```

In the cellProvider (line ~1055), when building the `PostListPostViewModel`, pass `blurNsfw: preferencesService.blurNsfw` and `isRevealed: revealedNsfwPostIds.contains(row.id)`. Set `cell.revealNsfwTapped` to insert the id and reconfigure that row:

```swift
                cell.revealNsfwTapped = { [weak self] in
                    guard let self else { return }
                    revealedNsfwPostIds.insert(row.id)
                    reconfigureItems([item]) // re-run cellProvider for this row
                }
```

Use the existing single-item reconfigure path (mirror `reconfigureVisibleCells`, but for one item id). If only a bulk reconfigure exists, call it.

- [ ] **Step 5: Observe the blur stream (re-apply in place, no refetch) + frontpage sync**

Add an observer next to the `showNsfwStream` observer (PostListViewController ~line 588). Unlike show/hide, **do not** `reloadFeed()` — blur is a pure render change:

```swift
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await value in preferencesService.blurNsfwStream {
                if Task.isCancelled { break }
                if first { first = false; continue }
                reconfigureVisibleCells() // re-read isThumbnailBlurred
                if case .frontpage = viewModel.feed.feedType,
                   !viewModel.accountScope.isSignedOut
                {
                    let scope = viewModel.accountScope
                    Task { try? await scope.lemmyService.setBlurNsfw(value) }
                }
            }
        })
```

- [ ] **Step 6: `make project` + build.** Expected: builds clean.

- [ ] **Step 7: Snapshot test (blurred vs revealed)**

Create `SpudSnapshotTests/PostListNsfwBlurSnapshotTests.swift`. Build a `PostListPostViewModel` fixture with `isNsfw = true, blurNsfw = true, isRevealed = false` and snapshot the configured `PostListPostCell`; then `isRevealed = true` and snapshot revealed. Follow the cell-snapshot pattern in the existing `PostDetailCommentSnapshotTests` / any `PostListPostCell` snapshot (fixtures with nil image URLs render placeholders deterministically).

```swift
import XCTest
import SnapshotTesting
@testable import Spud

final class PostListNsfwBlurSnapshotTests: XCTestCase {
    func test_nsfwThumbnail_blurred() {
        let cell = makeConfiguredCell(isNsfw: true, blurNsfw: true, isRevealed: false)
        assertSnapshot(of: cell, as: .image(size: cell.systemLayoutSizeFitting(...)))
    }
    func test_nsfwThumbnail_revealed() {
        let cell = makeConfiguredCell(isNsfw: true, blurNsfw: true, isRevealed: true)
        assertSnapshot(of: cell, as: .image(size: cell.systemLayoutSizeFitting(...)))
    }
}
```

Implement `makeConfiguredCell` using the existing snapshot fixture helpers (a `StaticImageService`, a fake `PostListRow`/view model). Record on first run, rerun to verify, then `git add` the PNGs (annex), commit.

- [ ] **Step 8: Format + commit**

```bash
mint run swiftformat Spud/Scenes/PostList SpudSnapshotTests/PostListNsfwBlurSnapshotTests.swift
git add Spud/Scenes/PostList SpudSnapshotTests/PostListNsfwBlurSnapshotTests.swift SpudSnapshotTests/__Snapshots__/PostListNsfwBlurSnapshotTests
git commit -m "feat: blur NSFW thumbnails with tap-to-reveal"
```

---

### Task 10: Blur the post-detail header image

**Files:**
- Modify: `Spud/Scenes/PostDetail/PostDetailHeaderCell.swift` (the lead image view + configure)
- Modify: the post-detail VC that owns the header (single `isRevealed` Bool for the open post; find it via the cell's configure call site)
- Test: `SpudSnapshotTests/PostDetailHeaderNsfwSnapshotTests.swift` (create) — or extend `PostDetailHeaderSnapshotTests`

**Interfaces:**
- Consumes: `PostRecord.isNsfw` / row `isNsfw`, `PreferencesService.blurNsfw`, `NsfwBlurOverlayView`.

- [ ] **Step 1: Add an overlay over the header lead image**

In `PostDetailHeaderCell.swift`, add an `NsfwBlurOverlayView` (with `showsCaption = true`) pinned over the lead image view (the same view the media-viewer tap uses). Expose `func setNsfwBlur(_ blurred: Bool, onReveal: @escaping () -> Void)`.

- [ ] **Step 2: Wire it in the header's configure**

Where the header cell is configured from the post, compute `blurred = post.isNsfw && preferencesService.blurNsfw && !headerNsfwRevealed` and call `setNsfwBlur(blurred) { headerNsfwRevealed = true; reconfigureHeader() }`. Add `private var headerNsfwRevealed = false` to the post-detail VC; reset it when a different post loads.

- [ ] **Step 3: `make project` + build.** Expected: builds clean.

- [ ] **Step 4: Snapshot test** — add `test_image_nsfwBlurred` to the header snapshot tests: a fixture with `isNsfw = true`, `blurNsfw = true`, unrevealed → blurred header. Record, verify, `git add` PNGs.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail SpudSnapshotTests
git add Spud/Scenes/PostDetail SpudSnapshotTests
git commit -m "feat: blur NSFW post-detail header image"
```

---

### Task 11: Shared NSFW badge

**Files:**
- Create: `Spud/Scenes/Shared/NsfwBadge.swift` (SwiftUI; the consumers here — Discover, community header — are SwiftUI)
- Modify: `Spud/Scenes/Discover/DiscoverView.swift` (replace inline `nsfwBadge` with the shared view)

**Interfaces:**
- Produces: `struct NsfwBadge: View` rendering the red "NSFW" pill (extracted verbatim from `DiscoverView.nsfwBadge`).

- [ ] **Step 1: Create the badge** (lift the exact styling from `DiscoverView.swift:400-408`):

```swift
import SwiftUI

/// The single NSFW pill used across Discover, community headers, and post
/// surfaces. One definition so the badge reads identically everywhere.
struct NsfwBadge: View {
    var body: some View {
        Text("NSFW")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color(.systemRed), in: RoundedRectangle(cornerRadius: 4))
    }
}
```

- [ ] **Step 2: Use it in Discover** — replace the inline `nsfwBadge` computed property usage with `NsfwBadge()` and delete the now-dead private `nsfwBadge` var.

- [ ] **Step 3: `make project` + build + commit**

```bash
mint run swiftformat Spud/Scenes/Shared/NsfwBadge.swift Spud/Scenes/Discover/DiscoverView.swift
git add Spud/Scenes/Shared/NsfwBadge.swift Spud/Scenes/Discover/DiscoverView.swift
git commit -m "refactor: extract shared NsfwBadge"
```

---

### Task 12: Blur NSFW community art + badge the community header

**Files:**
- Modify: `Spud/Scenes/Discover/CommunityIcon.swift` (blur when NSFW + show on)
- Modify: `Spud/Scenes/Community/Content/CommunityHeaderView.swift` (blur banner/icon + show `NsfwBadge`)

**Interfaces:**
- Consumes: community `isNsfw`, `PreferencesService.blurNsfw` (read via the existing environment/DI used by these SwiftUI views), `NsfwBadge` (Task 11).

- [ ] **Step 1: Add a blur modifier to `CommunityIcon`**

Add an `isNsfwBlurred: Bool = false` parameter. When true, overlay `.overlay { Rectangle().fill(.ultraThinMaterial) }` (and clip to the same rounded shape) so the icon reads as obscured. Call sites that have the community's `isNsfw` + the blur preference pass `isNsfwBlurred: isNsfw && blurNsfw`. (Reveal-on-tap for community art is optional; v1 may keep community art blurred-when-NSFW — see spec Open questions. Keep it always-blurred here unless a tap target is trivial to add.)

- [ ] **Step 2: Badge + blur the community header**

In `CommunityHeaderView.swift`, when the community `isNsfw`, show `NsfwBadge()` next to the title, and when `blurNsfw` is also on, apply the same `.ultraThinMaterial` overlay to the banner image.

- [ ] **Step 3: `make project` + build + manual check.** Open an NSFW community → header art blurred + NSFW badge; Discover rows show blurred icons when Show on + Blur on.

- [ ] **Step 4: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Discover/CommunityIcon.swift Spud/Scenes/Community/Content/CommunityHeaderView.swift
git add Spud/Scenes/Discover/CommunityIcon.swift Spud/Scenes/Community/Content/CommunityHeaderView.swift
git commit -m "feat: blur NSFW community art + badge community header"
```

---

### Task 13: Gate NSFW out of Search + composer picker

**Files:**
- Modify: `Spud/Scenes/Search/SearchResults.swift` (add a pure NSFW filter)
- Modify: `Spud/Scenes/Search/SearchViewModel.swift` (apply when `show_nsfw` off; observe stream)
- Modify: `Spud/Scenes/Composer/CommunityPickerViewController.swift` (drop NSFW community results when `show_nsfw` off)
- Test: `SpudTests/SearchResultsNsfwFilterTests.swift` (create; app-target test)

**Interfaces:**
- Produces: `SearchResults.filteringNsfw(_ removeNsfw: Bool) -> SearchResults` (pure; drops NSFW communities + NSFW posts when `removeNsfw` is true).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Spud

final class SearchResultsNsfwFilterTests: XCTestCase {
    func test_filteringNsfw_dropsNsfwCommunitiesAndPosts() {
        let results = SearchResults(/* one NSFW community, one SFW community,
                                       one NSFW post, one SFW post */)
        let filtered = results.filteringNsfw(true)
        XCTAssertFalse(filtered.communities.contains { $0.isNsfw })
        XCTAssertFalse(filtered.posts.contains { $0.isNsfw })
        // SFW entries survive:
        XCTAssertEqual(filtered.communities.count, 1)
        XCTAssertEqual(filtered.posts.count, 1)
    }
}
```

Adapt to the real `SearchResults` shape (inspect its stored arrays and the NSFW flag each result row carries — community rows carry `isNsfw`; post rows expose `nsfw` from their `PostView`). If results store decoded LemmyKit `CommunityView`/`PostView`, read `.community.nsfw` / `.post.nsfw`.

- [ ] **Step 2: Run to verify it fails.** Expected: FAIL — no `filteringNsfw`.

- [ ] **Step 3: Implement the pure filter** in `SearchResults.swift`:

```swift
    /// Returns a copy with NSFW communities and posts removed. Used to keep
    /// NSFW content out of search and pickers when the user has not opted in
    /// (`show_nsfw` off). Lemmy's search API has no server NSFW filter, so this
    /// is client-side.
    func filteringNsfw(_ removeNsfw: Bool) -> SearchResults {
        guard removeNsfw else { return self }
        var copy = self
        copy.communities = communities.filter { !$0.isNsfw }
        copy.posts = posts.filter { !$0.isNsfw }
        return copy
    }
```

(Match the real property names/types; if `communities`/`posts` are `let`, build a new `SearchResults` via its initializer.)

- [ ] **Step 4: Apply it in `SearchViewModel`**

In `performSearch`, after building results, gate on the preference and store the filtered value:

```swift
            let decoded = SearchResults(response: response)
            results = decoded.filteringNsfw(!preferencesService.showNsfw)
```

Add a `blurNsfwStream`-style observer of `showNsfwStream` so an open Search re-filters when the preference flips (re-run the last query or re-filter the cached response). Inject `preferencesService` if not already available to the view model.

- [ ] **Step 5: Apply it in the composer picker**

In `CommunityPickerViewController.swift`, where search results are received, drop NSFW communities when `preferencesService.showNsfw` is off (same `filteringNsfw` or an inline `.filter { showNsfw || !$0.isNsfw }`).

- [ ] **Step 6: Run the app-target test + build.** Expected: PASS + builds.

- [ ] **Step 7: Manual check.** With Show NSFW off, search a known NSFW community name → it does not appear; composer community search likewise. Deep-linking to it still opens it.

- [ ] **Step 8: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Search Spud/Scenes/Composer/CommunityPickerViewController.swift SpudTests/SearchResultsNsfwFilterTests.swift
git add Spud/Scenes/Search Spud/Scenes/Composer/CommunityPickerViewController.swift SpudTests/SearchResultsNsfwFilterTests.swift
git commit -m "feat: gate NSFW out of search and composer picker"
```

---

### Task 14: One-time age acknowledgment on enabling Show NSFW

**Files:**
- Modify: `Spud/Services/Preferences/PreferencesService.swift` (`hasAcknowledgedNsfwAge` flag, protocol + concrete)
- Modify: `Spud/Scenes/Preferences/PreferencesPostMarkingAndHidingView.swift` (alert before enabling)
- Modify: `Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift` (alert before enabling)

**Interfaces:**
- Produces: `PreferencesServiceType.hasAcknowledgedNsfwAge: Bool { get set }` (default `false`).

- [ ] **Step 1: Add the flag** (protocol + concrete, mirroring `showNsfw` but no stream needed):

Protocol:
```swift
    var hasAcknowledgedNsfwAge: Bool { get set }
```
Concrete:
```swift
    @UserDefaultsBacked(key: "hasAcknowledgedNsfwAge")
    var hasAcknowledgedNsfwAge: Bool = false
```

- [ ] **Step 2: Gate the Settings Show-NSFW toggle**

In `PreferencesPostMarkingAndHidingView.swift`, add `@State private var showingAgeGate = false`. Change the `showNsfw` binding setter so enabling-when-not-acknowledged opens the gate instead of writing:

```swift
    private var showNsfw: Binding<Bool> {
        .init { viewModel.showNsfw } set: { newValue in
            if newValue, !viewModel.hasAcknowledgedNsfwAge {
                showingAgeGate = true
            } else {
                viewModel.updateShowNsfw(newValue)
            }
        }
    }
```

Add a confirmation alert on the `Form`:

```swift
        .alert("Show adult content?", isPresented: $showingAgeGate) {
            Button("Cancel", role: .cancel) {}
            Button("Show NSFW") {
                viewModel.acknowledgeNsfwAge()
                viewModel.updateShowNsfw(true)
            }
        } message: {
            Text("By continuing you confirm you are of legal age to view adult material.")
        }
```

Expose on `PreferencesViewModel`: `var hasAcknowledgedNsfwAge: Bool` (seeded from the service) and `func acknowledgeNsfwAge() { preferencesService?.hasAcknowledgedNsfwAge = true; hasAcknowledgedNsfwAge = true }`.

- [ ] **Step 3: Gate the Quick Switch Show-NSFW toggle** the same way (`@State` gate + alert + `viewModel.acknowledgeNsfwAge()` / `updateShowNsfw(true)` on confirm; add `hasAcknowledgedNsfwAge` + `acknowledgeNsfwAge()` to `QuickSwitchViewModel`).

- [ ] **Step 4: Build + manual check.** Fresh install: toggling Show NSFW on (either surface) shows the alert once; Cancel leaves it off; confirm enables it and the alert never returns.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Services/Preferences Spud/Scenes/Preferences Spud/Scenes/PostList/QuickSwitch
git add Spud/Services/Preferences/PreferencesService.swift Spud/Scenes/Preferences Spud/Scenes/PostList/QuickSwitch
git commit -m "feat: one-time age acknowledgment for Show NSFW"
```

---

### Task 15: Documentation

**Files:**
- Modify: `docs/features/nsfw-content.md`
- Modify: `docs/features/README.md` (capability table + "Feature coverage by area" map)
- Re-verify (touch if needed): `docs/features/discover.md`, `post-thumbnails.md`, `community-screen.md`, `new-post.md`, `feeds-and-sorting.md`

- [ ] **Step 1: Update `nsfw-content.md`**
  - Remove the out-of-scope line "There is no separate 'blur NSFW' mode...".
  - Add a "Blur" subsection: blur is independent of show/hide, default on, obscures NSFW thumbnails + post-detail header + community art behind a tap-to-reveal overlay (session-only per-post reveal), toggled in Settings and Quick Switch, disabled when Show is off, synced to the server's `blur_nsfw` on the frontpage feed.
  - Add the age-acknowledgment behavior.
  - Update the discovery section: gating now also covers the global Search scene and the composer community picker (deep-link / subscribed access preserved).
  - Add scenarios: "NSFW media is blurred until tapped", "Search hides NSFW when Show is off", "Age acknowledgment on first enable".

- [ ] **Step 2: Update `README.md`** — bump the NSFW row in the capability table to mention blur; update the by-area map entry.

- [ ] **Step 3: Re-read the adjacent docs** listed above and add a one-line cross-reference where blur/gating is now relevant (e.g. `post-thumbnails.md` notes NSFW blur; `community-screen.md` notes the header badge/blur). No `.swift` links.

- [ ] **Step 4: Commit**

```bash
git add docs/features
git commit -m "docs: document NSFW blur + coherent NSFW handling"
```

---

## Self-Review

**Spec coverage:**
- Two independent axes / blur default on / disable-when-off → Tasks 3, 6, 7, semantics honored throughout. ✓
- `post.isNsfw` data gap (migration v20) → Task 1. ✓
- `PostListRow.isNsfw = post OR community` → Task 2. ✓
- Preference + server sync mirroring `show_nsfw` → Tasks 3, 4, 5, 9 (frontpage observer). ✓
- Blur overlay (UIVisualEffectView, not Core Image) + session per-post reveal → Tasks 8, 9. ✓
- Thumbnails + post-detail header → Tasks 9, 10. ✓
- Community art blur → Task 12. ✓
- Discovery gating extended to Search + composer picker, deep-link/subscribed preserved → Task 13. ✓
- Shared NSFW badge → Tasks 11, 12. ✓
- Age acknowledgment → Task 14. ✓
- Widget unchanged → no task (correct; nothing to change). ✓
- Tests + docs → per-task tests + Task 15. ✓

**Placeholder scan:** The spec's two non-blocking Open Questions are resolved to defaults in the plan: community-art reveal is "always blurred when NSFW" in v1 (Task 12), and the badge lives as a SwiftUI view in `Spud/Scenes/Shared` (Task 11). A few tests reference repo-specific seeding helpers (`seedAccountAndSite`, `LemmyServiceTestHarness`, the `SearchResults` shape) that must be matched to the actual sibling-test infrastructure — these are flagged inline as "copy from <file>", not left as bare TODOs, because the exact helper names are discoverable only by reading those test files at implementation time.

**Type consistency:** `isNsfw` is the name used on `PostRecord`, `PostListRow`, and community throughout; `blurNsfw` is the preference name on the service, both view models, and `setBlurNsfw`/`setAccountBlurNsfw`; `NsfwBlurOverlayView.setRevealed(_:)` and `PostListThumbnailImageView.isBlurred` are used consistently between Tasks 8 and 9.

## Risks / things to watch

- **Account table DDL** (Task 4 Step 4): confirm whether the `account` table needs an explicit `blurNsfw` column add. If GRDB encodes the full record and the table was created with explicit columns, the add is required; otherwise reads will fail decoding. Verify against the `account` table creation in `AppDatabase+Migrations.swift`.
- **Single-row reconfigure** (Task 9 Step 4): the controller may only expose a bulk `reconfigureVisibleCells`. Reuse it if a per-item path is absent — slightly heavier but correct.
- **Fake api `saveUserSettings` capture** (Task 5): extend the test fake to record `blurNSFW` if it doesn't already.
- **Snapshot annex flow**: record/verify one class at a time; `git add` the PNGs after a green verify; never `git annex restage` between record and verify.
