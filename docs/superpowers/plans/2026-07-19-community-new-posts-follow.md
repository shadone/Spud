# Community New-Posts Follow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "Notify About New Posts" on a community — a third reminder kind (`communityPosts`) that polls a community's newest posts against a published-timestamp watermark and fires a local notification on >= 1 new post, surfaced through the existing Inbox Reminders segment.

**Architecture:** Extends the shipped reminders substrate (spec: `docs/superpowers/specs/2026-07-19-community-new-posts-follow-design.md`). No schema migration: the `reminder` table's columns are reused (`postServerId` carries the community server id, `apId` the community actorId, `baselineAt` the watermark). New `ReminderService` set/remove/poll API, a feed-less `LemmyService` newest-post-dates wrapper, a second sweep branch in `SchedulerService` (BGAppRefresh inherits it), Inbox branches, and four entry-point surfaces with centralized copy.

**Tech Stack:** Swift 6 strict concurrency, GRDB, Swift Testing (`struct` suites, `@Test`, `#expect`), UIKit + SwiftUI (Subscriptions tab), XcodeGen.

## Global Constraints

- Repo: `/Users/denis/dev/info.ddenis/Spud/Spud` (branch off local `main`; execution in a worktree — use worktree-rooted paths, never the main-checkout absolute paths).
- After ADDING any file: `make project` (XcodeGen) before building.
- Unit tests are Swift Testing; run with `make test-only ONLY=<target>`; snapshot tests with `make snapshot` (reference iPhone 17 Pro sim only). A targeted class run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests/<Class> -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test`.
- GRDB dates: `reminder`'s date columns are ISO-8601 TEXT — always bind `Date` values in SQL arguments, never `timeIntervalSince1970`.
- The `kind` string for the new case is exactly `"communityPosts"`; the notification request id pattern is exactly `"reminder-\(accountId)-\(communityServerId)-0-communityPosts"`.
- Copy is centralized: every surface reads titles/symbols/toasts from `CommunityNotifyLabel` (Task 5). Menu title: "Notify About New Posts". Symbols: `bell.badge` (off) / `bell.badge.fill` (on) — NOT `bell`/`bell.slash`/`bell.fill` (taken by Mute/Unmute and the Remind Me submenu).
- No emojis anywhere. Conventional commit subjects. `mint run swiftformat <changed paths>` BEFORE the final test verify of each task. Commit with explicit paths (never `git add -A`).
- Three doc tiers on every task: `///` API docs, why-comments, and (Task 7) `docs/features/`.

---

### Task 1: SpudDataKit core — kind, rule, queries, writes

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Records/ReminderRecord.swift`
- Create: `SpudDataKit/Services/Reminders/CommunityFollowRule.swift`
- Modify: `SpudDataKit/Services/AppDatabase/ReminderQueries.swift`
- Modify: `SpudDataKit/Services/AppDatabase/ReminderWrites.swift`
- Modify: `SpudDataKit/Services/AppDatabase/ReminderObservations.swift`
- Test: `SpudDataKitTests/Reminders/CommunityFollowRuleTests.swift` (create), `SpudDataKitTests/AppDatabase/ReminderWritesTests.swift` (extend)

**Interfaces:**
- Produces: `ReminderRecord.Kind.communityPosts`; `CommunityFollowRule.shouldFire(newPosts:) -> Bool`, `CommunityFollowRule.saturationThreshold: Int` (= 10), `CommunityFollowRule.pollInterval` (forwards `ReminderActivityRule.pollInterval`); `AppDatabase.dueCommunityFollowsSync(accountId:asOf:) -> [ReminderRecord]`; `AppDatabase.rearmCommunityFollow(id:watermark:nextCheckAt:firedAt:) async throws`; `activeReminderKindsSync` now also returns `"communityPosts"` when a follow is `scheduled` or `fired`; `AppDatabase.observeCommunityFollowServerIds(forAccountId:) -> AsyncStream<Set<Int64>>`.

- [ ] **Step 1: Extend `ReminderRecord`.** Add the case and document the column reuse on the type's doc comment (table: postServerId = community server id, apId = community actorId, titleSnapshot = community title, thumbnailUrl = icon URL, baselineAt = watermark [newest post `published` seen], baselineCount/fireAt = nil, rootCommentServerId = 0):

```swift
    /// Typed view of the `kind` raw string.
    enum Kind: String {
        case time
        case activity
        /// A community "new posts" follow. Reuses the post-centric columns —
        /// see the type doc comment's column-reuse table.
        case communityPosts
    }
```

- [ ] **Step 2: Write failing rule tests** (`CommunityFollowRuleTests.swift`, Swift Testing, `import Testing`, `@testable import SpudDataKit`):

```swift
struct CommunityFollowRuleTests {
    @Test func firesOnOneNewPost() { #expect(CommunityFollowRule.shouldFire(newPosts: 1)) }
    @Test func firesOnManyNewPosts() { #expect(CommunityFollowRule.shouldFire(newPosts: 12)) }
    @Test func neverFiresOnZero() { #expect(!CommunityFollowRule.shouldFire(newPosts: 0)) }
    @Test func pollIntervalMatchesActivityThrottle() {
        #expect(CommunityFollowRule.pollInterval == ReminderActivityRule.pollInterval)
    }
}
```

- [ ] **Step 3: Run to verify failure** (type not found), then implement `CommunityFollowRule.swift` (mirror `ReminderActivityRule`'s header style):

```swift
/// The fixed fire rule for a community "new posts" follow. Deliberately NOT
/// the activity rule's 5-or-24h shape: meta/announcement communities post
/// rarely, so >= 1 new post fires (batched — one notification per check
/// regardless of count). Zero new posts never fires.
public enum CommunityFollowRule {
    /// When the new-post count equals the fetched page size and reaches this
    /// threshold, the notification body reads "N+ new posts" — there may be
    /// more beyond the single fetched page.
    public static let saturationThreshold = 10

    /// Same throttle as activity follows; forwards `ReminderActivityRule`'s
    /// constant so every write site stays in agreement.
    public static let pollInterval: TimeInterval = ReminderActivityRule.pollInterval

    public static func shouldFire(newPosts: Int) -> Bool {
        newPosts >= 1
    }
}
```

- [ ] **Step 4: Queries.** In `ReminderQueries.swift` add `dueCommunityFollowsSync` (clone `dueActivityRemindersSync`, `kind = communityPosts`, same `status IN (scheduled, fired)` + `nextCheckAt <= ?` shape, `asOf` bound as `Date`). Extend `activeReminderKindsSync`'s SQL with a third alternative `OR (kind = ? AND status IN (?, ?))` binding `Kind.communityPosts.rawValue, Status.scheduled.rawValue, Status.fired.rawValue`, and extend its doc comment (community follows are active while scheduled OR fired, same rationale as activity).

- [ ] **Step 5: Writes.** In `ReminderWrites.swift` add (mirror `rearmActivityReminder`; `baselineCount` untouched — community rows keep it nil):

```swift
    /// Fires a community follow from the poll: `status = .fired`, `unseen =
    /// true`, `lastNotifiedAt = firedAt`, watermark (`baselineAt`) re-armed to
    /// the newest post `published` observed, `nextCheckAt` pushed forward so
    /// the follow keeps watching. A no-op if `id` doesn't exist.
    func rearmCommunityFollow(id: Int64, watermark: Date, nextCheckAt: Date, firedAt: Date) async throws {
        try await writer.write { db in
            guard var record = try ReminderRecord.fetchOne(db, key: id) else { return }
            record.status = ReminderRecord.Status.fired.rawValue
            record.unseen = true
            record.lastNotifiedAt = firedAt
            record.baselineAt = watermark
            record.nextCheckAt = nextCheckAt
            try record.update(db)
        }
    }
```

- [ ] **Step 6: Observation.** In `ReminderObservations.swift` add `observeCommunityFollowServerIds(forAccountId accountId: Int64) -> AsyncStream<Set<Int64>>` — a `ValueObservation` (start with `.async(onQueue: .global(qos: .userInitiated))`, matching the file's existing helpers) over `SELECT postServerId FROM reminder WHERE accountId = ? AND kind = 'communityPosts' AND status IN ('scheduled','fired')`, mapped to `Set<Int64>`. Drives the Subscriptions-tab bell state (Task 6).

- [ ] **Step 7: Extend `ReminderWritesTests`** with community-follow cases: `rearmCommunityFollow` sets fired/unseen/watermark and preserves `baselineCount = nil`; `dueCommunityFollowsSync` returns only `communityPosts` rows due `asOf` (insert one due activity row + one due community row, expect only the community row); `activeReminderKindsSync` returns `communityPosts` for a scheduled AND a fired follow, and — crucially — a community follow and an activity reminder on the SAME numeric target id (`postServerId = 42` both) are returned as two distinct kinds. Also `removeAllReminders` deletes community rows (insert one, expect table empty after).

- [ ] **Step 8: Run, format, commit.**

Run: `make test-only ONLY=SpudDataKitTests` (or targeted `-only-testing:SpudDataKitTests/CommunityFollowRuleTests -only-testing:SpudDataKitTests/ReminderWritesTests`). Expected: pass.

```bash
mint run swiftformat SpudDataKit/ SpudDataKitTests/ && make project
git add <the six files> && git commit -m "feat: add communityPosts reminder kind, rule, and DB plumbing"
```

---

### Task 2: ReminderService follow API + poll, notification content

**Files:**
- Modify: `SpudDataKit/Services/Reminders/ReminderService.swift`
- Modify: `SpudDataKit/Services/Reminders/ReminderNotificationScheduling.swift` (factory)
- Test: `SpudDataKitTests/Reminders/ReminderServiceCommunityFollowTests.swift` (create), `SpudTests/Reminders/ReminderNotificationContentTests.swift` (extend)

**Interfaces:**
- Consumes: Task 1's `CommunityFollowRule`, `dueCommunityFollowsSync`, `rearmCommunityFollow`.
- Produces:
  - `ReminderService.setCommunityFollow(communityServerId: Int64, communityActorId: String, name: String, title: String, instanceHost: String, iconUrl: String?) async throws`
  - `ReminderService.removeCommunityFollow(communityServerId: Int64) async throws`
  - `ReminderService.pollDueCommunityFollows(asOf: Date, postDatesFetcher: @Sendable (_ communityServerId: Int64, _ communityActorId: String) async -> [Date]?) async`
  - `ReminderNotificationFactory.communityFollowContent(title: String, communityName: String, instanceHost: String, newCount: Int, isSaturated: Bool) -> ReminderNotificationContent`

- [ ] **Step 1: Write failing service tests.** New suite using the existing `FakeReminderNotificationScheduler` (declared in `ReminderServiceTests.swift` — shared across the target) and the file-local `makeService`-style helper pattern (in-memory `AppDatabase`, accountId 1). Cases:

```swift
struct ReminderServiceCommunityFollowTests {
    // setCommunityFollow persists kind=communityPosts, postServerId=42, apId=actorId,
    // baselineAt == the injected now-ish (watermark), baselineCount == nil, fireAt == nil,
    // nextCheckAt ~ now + CommunityFollowRule.pollInterval, status scheduled.
    @Test func setPersistsFollowRow() async throws { ... }
    // Second set on the same community replaces (upsert), not duplicates.
    @Test func setIsIdempotentPerCommunity() async throws { ... }
    // removeCommunityFollow deletes the row; no scheduler.cancel call is made
    // (community follows never persist a notificationRequestId).
    @Test func removeDeletesRowWithoutCancel() async throws { ... }
    // A community follow on id 42 and an ACTIVITY reminder on post 42 coexist
    // and remove independently (kind disambiguates the shared column).
    @Test func noCrosstalkWithActivityOnSameNumericId() async throws { ... }
    // Poll: fetcher returns 3 dates > watermark -> scheduler.postNow called once with
    // requestId "reminder-1-42-0-communityPosts"; row re-armed: baselineAt == max(dates),
    // status fired, unseen true, nextCheckAt bumped.
    @Test func pollFiresOnNewPostsAndRearmsWatermark() async throws { ... }
    // Poll: all dates <= watermark -> no postNow, nextCheckAt bumped, watermark untouched.
    @Test func pollNoFireOnNoNewPosts() async throws { ... }
    // Poll: fetcher returns nil -> no postNow, nextCheckAt bumped, watermark untouched.
    @Test func pollBumpsOnFetchFailure() async throws { ... }
    // Poll: only rows with nextCheckAt <= asOf are checked (a not-yet-due row's
    // fetcher is never invoked).
    @Test func pollHonorsThrottle() async throws { ... }
}
```

Write them with real assertions (read rows back via `appDatabase.reminderSync(accountId:postServerId:rootCommentServerId:kind:)`; scheduler call capture via the fake's recorded arrays). Run: expected FAIL (methods undefined).

- [ ] **Step 2: Implement the service API** in `ReminderService.swift` (new `// MARK: - Community follows` section; mirror the activity methods' doc-comment style, including the column-reuse note):

```swift
    public func setCommunityFollow(
        communityServerId: Int64, communityActorId: String,
        name: String, title: String, instanceHost: String, iconUrl: String?
    ) async throws {
        let now = Date()
        let record = ReminderRecord(
            accountId: accountId,
            postServerId: communityServerId,        // column reuse — see ReminderRecord
            apId: communityActorId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue,
            nextCheckAt: now.addingTimeInterval(CommunityFollowRule.pollInterval),
            baselineCount: nil,
            baselineAt: now,                        // the watermark
            status: ReminderRecord.Status.scheduled.rawValue,
            unseen: false,
            notificationRequestId: nil,
            titleSnapshot: title,
            communityName: name,
            instanceHost: instanceHost,
            thumbnailUrl: iconUrl
        )
        try await appDatabase.upsertReminder(record)
        _ = await isAuthorized() // primes the permission prompt, same as setActivityReminder
    }

    public func removeCommunityFollow(communityServerId: Int64) async throws {
        try await appDatabase.removeReminder(
            accountId: accountId, postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue
        )
    }
```

- [ ] **Step 3: Implement the poll** (mirror `pollDueActivityReminders`'s structure, diagnostics, and never-throws contract; private request-id helper `communityFollowNotificationRequestId(forCommunityServerId:)` returning `"reminder-\(accountId)-\(communityServerId)-\(ReminderRecord.wholePostSentinel)-\(ReminderRecord.Kind.communityPosts.rawValue)"`):

```swift
    public func pollDueCommunityFollows(
        asOf: Date,
        postDatesFetcher: @Sendable (_ communityServerId: Int64, _ communityActorId: String) async -> [Date]?
    ) async {
        let due = appDatabase.dueCommunityFollowsSync(accountId: accountId, asOf: asOf)
        let nextCheckAt = asOf.addingTimeInterval(CommunityFollowRule.pollInterval)
        for follow in due {
            guard let id = follow.id else { continue }
            guard let dates = await postDatesFetcher(follow.postServerId, follow.apId) else {
                await bumpNextCheck(id: id, nextCheckAt: nextCheckAt)
                await diagnostics.record(category: .reminder, level: .notice,
                    event: "poll.community.fetchFailed",
                    message: "Community follow poll could not fetch newest posts (or the community is muted)",
                    instance: follow.instanceHost,
                    metadata: ["communityServerId": String(follow.postServerId)])
                continue
            }
            // Malformed-row fallback mirrors the activity poll: a follow always
            // sets baselineAt at creation, so nil only means a damaged row —
            // treat everything as already-seen rather than firing on the backlog.
            let watermark = follow.baselineAt ?? asOf
            let newPosts = dates.filter { $0 > watermark }.count
            if CommunityFollowRule.shouldFire(newPosts: newPosts) {
                let isSaturated = newPosts == dates.count && newPosts >= CommunityFollowRule.saturationThreshold
                let content = ReminderNotificationFactory.communityFollowContent(
                    title: follow.titleSnapshot, communityName: follow.communityName,
                    instanceHost: follow.instanceHost, newCount: newPosts, isSaturated: isSaturated)
                await scheduler.postNow(
                    requestId: communityFollowNotificationRequestId(forCommunityServerId: follow.postServerId),
                    content: content)
                do {
                    try await appDatabase.rearmCommunityFollow(
                        id: id, watermark: dates.max() ?? watermark,
                        nextCheckAt: nextCheckAt, firedAt: asOf)
                } catch { logger.error("pollDueCommunityFollows: rearm(\(id)) failed: \(String(describing: error), privacy: .public)") }
                await diagnostics.record(category: .reminder, level: .info,
                    event: "poll.community.fired", message: "Community follow fired",
                    instance: follow.instanceHost,
                    metadata: ["communityServerId": String(follow.postServerId), "newPosts": String(newPosts)])
            } else {
                await bumpNextCheck(id: id, nextCheckAt: nextCheckAt)
            }
        }
    }
```

- [ ] **Step 4: Factory.** Add `communityFollowContent` to `ReminderNotificationFactory`. Routing: verify `URL.SpudInternalLink`'s community case signature (grep `case community` in the `SpudInternalLink` definition — same module reachability as the factory's existing `objectAtURL` use) and how an `InstanceActorId` is built from a stored host string (see `SiteListRow.forTypedInstance` for the existing bare-host construction); on construction failure degrade to `routingURLString: ""` with a logged error, mirroring the existing guards. Body copy (four localized formats, mirroring `activityReminderContent`'s singular/plural split, plus the saturated variant):
  - singular: `"1 new post · c/%2$@@%3$@"` (format `"%1$d new post · c/%2$@@%3$@"`)
  - plural: `"%1$d new posts · c/%2$@@%3$@"`
  - saturated: `"%1$d+ new posts · c/%2$@@%3$@"`
  Title = the community title. Extend `ReminderNotificationContentTests` (SpudTests): singular body, plural body, saturated body, and routing URL points at the community deep link (assert prefix/host+path, not the whole string).

- [ ] **Step 5: Run all new/extended suites, format, commit.**

Run: `make test-only ONLY=SpudDataKitTests` then `make test-only ONLY=SpudTests` (targeted classes are fine). Expected: pass.

```bash
mint run swiftformat SpudDataKit/ SpudDataKitTests/ SpudTests/
git add <files> && git commit -m "feat: community follow set/remove/poll on ReminderService"
```

---

### Task 3: LemmyService newest-post-dates wrapper + scheduler sweep

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (protocol `LemmyServiceType` at top + implementation)
- Modify: `SpudDataKit/Services/Scheduler/SchedulerService.swift`
- Modify: `Spud/App/DependencyContainer.swift` (only if a new init seam is added — see Step 3)
- Test: `SpudDataKitTests/` — extend whichever suite already stubs `ClientTransport` for `LemmyService` (see `LemmyServiceContentNotFoundTests` for the stub pattern) with a dates-mapping test.

**Interfaces:**
- Consumes: Task 2's `pollDueCommunityFollows`.
- Produces: `LemmyServiceType.fetchCommunityNewestPostDates(communityId: Int64, showNsfw: Bool) async -> [Date]?` — best-effort nil on any failure; protocol gets a default always-nil implementation (mirror `fetchSubtreeChildCount`'s default) so existing fakes keep compiling.

- [ ] **Step 1: Protocol + implementation.** Declare on `LemmyServiceType` with a doc comment (feed-less one-shot; nothing persisted; only `published` stamps are read) and a default `nil` extension implementation. Implement on `LemmyService`:

```swift
    public func fetchCommunityNewestPostDates(communityId: Int64, showNsfw: Bool) async -> [Date]? {
        do {
            let (sort, timeRange) = Lemmy.SortType.New.neutralPostSort
            let page = try await api.getPostsNeutral(
                listingType: .All, sort: sort, communityId: communityId,
                timeRange: timeRange, showNsfw: showNsfw, pageCursor: nil)
            return page.items.map { /* the PostView's published Date */ }
        } catch {
            logger.error("fetchCommunityNewestPostDates(\(communityId)) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
```

Verify in place: the exact `Page` items accessor and the `PostView` published-date key path (see how `fetchFeed`'s import path reads `post.published` — reuse the same accessor; it may be a string needing the importer's date parsing, in which case reuse that exact parsing helper). Verify `.New.neutralPostSort` compiles from this file (it's in `NeutralSortMapping.swift`, same module).

- [ ] **Step 2: Add the mapping test** using the stub-`ClientTransport` pattern: stub `GET` posts response with three posts at known published stamps, expect the returned `[Date]` to match; stub an HTTP 500, expect `nil`.

- [ ] **Step 3: Sweep.** In `SchedulerService.pollActivityRemindersSweep()`, after the existing `pollDueActivityReminders` call inside the per-keychainId loop, add the community poll with its own fetcher (same local-binding discipline for Swift 6):

```swift
            let showNsfw = showNsfwProvider()
            let communityFetcher: @Sendable (Int64, String) async -> [Date]? = { communityServerId, communityActorId in
                // Muted community: skip the check entirely (nil -> nextCheckAt bumps,
                // watermark untouched) - notifications pause while muted and the
                // accumulated posts fire once as a single batch after unmute.
                guard !appDatabase.isCommunityMutedSync(forKeychainId: keychainId, communityActorId: communityActorId) else {
                    return nil
                }
                return await lemmy.fetchCommunityNewestPostDates(communityId: communityServerId, showNsfw: showNsfw)
            }
            await accountService
                .reminderService(forAccountKeychainId: keychainId)
                .pollDueCommunityFollows(asOf: now(), postDatesFetcher: communityFetcher)
```

`showNsfwProvider` is a new `SchedulerService` init seam `@Sendable () -> Bool` with default `{ true }` (keeps existing constructions compiling), wired in `DependencyContainer` to the same preferences value `PostListViewModel` passes to `fetchFeed` (`preferencesService.showNsfw` — `SchedulerService` init runs on the main actor, so capture the service and read live inside the closure only if `PreferencesService` is Sendable-safe; otherwise snapshot per tick the way `reminderNotificationsEnabled` is wired at line ~89 of `DependencyContainer` — copy that seam's exact shape). Update the sweep's doc comment (it now polls both kinds).

- [ ] **Step 4: Build + full DataKit tests, format, commit.** `make test-only ONLY=SpudDataKitTests`. Note: `SchedulerService` init changes can cascade into test doubles — build the full test plan (`make test`) if `SpudTests` declares scheduler fakes. Expected: pass.

```bash
mint run swiftformat SpudDataKit/ Spud/ SpudDataKitTests/
git add <files> && git commit -m "feat: poll community follows from the scheduler sweep"
```

---

### Task 4: Inbox — status text, remove dispatch, tap routing, snapshots

**Files:**
- Modify: `Spud/Scenes/Inbox/ReminderStatusText.swift`
- Modify: `Spud/Scenes/Inbox/InboxViewModel.swift` (`removeReminder`)
- Modify: `Spud/Scenes/Inbox/InboxViewController.swift` (`openReminder`)
- Test: `SpudTests/Reminders/ReminderStatusTextTests.swift`, `SpudTests/InboxViewModelRemoveReminderTests.swift` (extend both); `SpudSnapshotTests/RemindersSegmentSnapshotTests.swift` (extend)

**Interfaces:**
- Consumes: `ReminderRecord.Kind.communityPosts`, `removeCommunityFollow(communityServerId:)`, `ReminderListRow` (unchanged shape — `postServerId` carries the community id for this kind).

- [ ] **Step 1: Failing status-text tests**: kind `communityPosts` + status `scheduled` -> "Watching for new posts"; + status `fired` -> "New posts · tap to catch up". Run; expect FAIL (falls through to the time branch).

- [ ] **Step 2: Implement** — in `ReminderStatusText.describe`, add before the activity branch:

```swift
        if reminder.kind == ReminderRecord.Kind.communityPosts.rawValue {
            return reminder.status == ReminderRecord.Status.fired.rawValue
                ? NSLocalizedString("New posts · tap to catch up",
                    comment: "Inbox reminder row status: a community new-posts follow has fired")
                : NSLocalizedString("Watching for new posts",
                    comment: "Inbox reminder row status: a community new-posts follow is live")
        }
```

- [ ] **Step 3: Remove dispatch.** In `InboxViewModel.removeReminder`'s switch, add a case before `default`:

```swift
                case ReminderRecord.Kind.communityPosts.rawValue:
                    try await accountScope.reminderService.removeCommunityFollow(
                        communityServerId: item.postServerId
                    )
```

Extend `InboxViewModelRemoveReminderTests` with a community-kind row asserting the community-follow removal path ran (same fixture pattern as the existing kinds).

- [ ] **Step 4: Tap routing.** In `InboxViewController.openReminder`, branch first on kind: for `communityPosts` build the community deep link from `reminder.communityName` + `reminder.instanceHost` (same `URL.SpudInternalLink` community case + `InstanceActorId` construction verified in Task 2 Step 4) and `AppCoordinator.shared.open(routingURL, in: window)`; other kinds keep the existing `objectAtURL(apId)` path. Guard: if the instance actor id can't be built from the stored host, fall back to doing nothing (mirrors the existing `URL(string:)` guard).

- [ ] **Step 5: Snapshots.** Extend `RemindersSegmentSnapshotTests` with two new reference states (community follow watching / fired), following the suite's existing seeded-row pattern. Record on the reference sim (`make snapshot` — first run records + fails, rerun verifies), `git add` ONLY the new reference images by explicit path.

- [ ] **Step 6: Run SpudTests + snapshot class, format, commit.**

```bash
mint run swiftformat Spud/ SpudTests/ SpudSnapshotTests/
git add <files + explicit new snapshot refs> && git commit -m "feat: community follows in the Inbox Reminders segment"
```

---

### Task 5: Centralized copy + UIKit entry points (community screen, Search)

**Files:**
- Create: `Spud/Utils/CommunityNotifyLabel.swift`
- Modify: `Spud/Scenes/Community/Content/CommunityViewController.swift`
- Modify: `Spud/Utils/ContextMenus/CommunityContextMenuBuilder.swift`
- Modify: `Spud/Scenes/Search/SearchViewController.swift` (host conformance ~line 955-1047)
- Test: extend the existing community context-menu builder tests (grep `CommunityContextMenuBuilder` under `SpudTests/`); add `SpudTests/CommunityNotifyLabelTests.swift`

**Interfaces:**
- Consumes: `setCommunityFollow`/`removeCommunityFollow` (via `accountScope.reminderService`), `activeReminderKindsSync` (community kind now included, Task 1).
- Produces: `enum CommunityNotifyLabel { static let title: String; static func symbol(isNotifying: Bool) -> String; static let toastOn: String; static let toastOff: String }`; `CommunityContextMenuHost` gains `communityIsNotifying(_ result: SearchCommunityResult) -> Bool` and `communityToggleNotify(_ result: SearchCommunityResult)`.

- [ ] **Step 1: `CommunityNotifyLabel`** (mirror `CommunitySubscribeButtonLabel`'s header style):

```swift
/// Centralized copy + symbols for the community "Notify About New Posts"
/// follow, shared by every surface (community overflow, Search context menu,
/// Subscriptions meta rows and subscribed-list menu) so the wording can't
/// drift. `bell.badge`, not `bell`/`bell.slash` - those belong to Mute/Unmute
/// (and the Remind Me submenu), which can appear in the same menus.
enum CommunityNotifyLabel {
    static var title: String {
        NSLocalizedString("Notify About New Posts", comment: "Menu action to follow a community for new-post notifications")
    }
    static func symbol(isNotifying: Bool) -> String {
        isNotifying ? "bell.badge.fill" : "bell.badge"
    }
    static var toastOn: String {
        NSLocalizedString("You'll be notified of new posts.", comment: "Toast confirming a community new-posts follow was set")
    }
    static var toastOff: String {
        NSLocalizedString("Stopped notifying.", comment: "Toast confirming a community new-posts follow was removed")
    }
}
```

Test: symbols differ by state; title non-empty (keeps the label enum honest under localization edits).

- [ ] **Step 2: Community screen.** In `CommunityViewController`: add `notifyMenuActions() -> [UIMenuElement]` appended to the stateGroup (after `favoriteMenuActions()` in `setup()`'s deferred stateGroup and in the header long-press menu at ~line 689). Pattern (identity from `viewModel`; instance host parsed from `viewModel.actorId`'s URL host, the same way `CommunityViewModel.isMeta` derives it; icon: use the view model's icon URL if it exposes one, else `nil`):

```swift
    private func notifyMenuActions() -> [UIMenuElement] {
        guard viewModel.actorId != nil else { return [] }
        let notifying = isNotifying()
        return [UIAction(
            title: CommunityNotifyLabel.title,
            image: UIImage(systemName: CommunityNotifyLabel.symbol(isNotifying: notifying)),
            state: notifying ? .on : .off
        ) { [weak self] _ in self?.toggleNotify() }]
    }
```

`isNotifying()`: resolve `accountRowIdSync(forKeychainId:)` then `activeReminderKindsSync(accountId:postServerId: Int64(serverCommunityId), rootCommentServerId: 0).contains(Kind.communityPosts.rawValue)` (mirror `PostReminderDispatching.activeReminderKinds`). `toggleNotify()`: `Haptics.tap()`, re-read live state at tap time (stale-menu discipline, mirror `toggleActivityReminder`), then `Task` calling `accountScope.reminderService.setCommunityFollow(...)` / `removeCommunityFollow(...)` with a toast (`ToastPresenter.shared.show` in the window) using `CommunityNotifyLabel.toastOn/.toastOff`; error path through the VC's alert service with the `.setReminder` context.

- [ ] **Step 3: Search.** Extend `CommunityContextMenuHost` with the two methods; in `CommunityContextMenuBuilder.menu`, append to the `openGroup` after `subscribeAction`:

```swift
        let notifying = host.communityIsNotifying(result)
        let notifyAction = UIAction(
            title: CommunityNotifyLabel.title,
            image: UIImage(systemName: CommunityNotifyLabel.symbol(isNotifying: notifying)),
            state: notifying ? .on : .off
        ) { [weak host] _ in host?.communityToggleNotify(result) }
        let openGroup = UIMenu(options: .displayInline, children: [openAction, subscribeAction, notifyAction])
```

Host conformance in `SearchViewController` mirrors its mute host methods: `communityIsNotifying` = the same `activeReminderKindsSync` read with `Int64(result.serverCommunityId)`; `communityToggleNotify` = the same toggle flow as Step 2 with identity from the result (`name: result.name`, `title: result.name` — the search result carries no separate display title, `instanceHost: URL(string: result.communityUrl)?.host` [guard-return if nil], `communityActorId: result.communityUrl`, `iconUrl: result.iconUrl?.absoluteString`).

- [ ] **Step 4: Builder tests.** Extend the existing builder test suite: the menu contains a "Notify About New Posts" action; its `state` reflects the host's `communityIsNotifying`; tapping-callback dispatch (the suite's existing recording-host fake pattern).

- [ ] **Step 5: Run SpudTests, format, commit.**

```bash
mint run swiftformat Spud/ SpudTests/ && make project   # new file added
git add <files> && git commit -m "feat: Notify About New Posts on community screen and Search menu"
```

---

### Task 6: Communities tab — meta-row bell + subscribed-list menu item

**Files:**
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsViewModel.swift`
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsView.swift`
- Test: extend the Subscriptions VM test suite (grep `SubscriptionsViewModel` under `SpudTests/`); snapshot only if a Subscriptions snapshot class already exists (do not introduce a new snapshot class for this).

**Interfaces:**
- Consumes: `observeCommunityFollowServerIds(forAccountId:)` (Task 1), `setCommunityFollow`/`removeCommunityFollow`, `CommunityNotifyLabel`.
- Produces: `SubscriptionsViewModel.notifyingCommunityIds: Set<Int64>`, `SubscriptionsViewModel.toggleNotify(_ item: MetaCommunityListItem)`, `MetaCommunityAboutRow` gains `isNotifying: Bool` + `onNotify: () -> Void`.

- [ ] **Step 1: VM.** Add `notifyingCommunityIds: Set<Int64> = []` driven by the Task 1 observation (start it alongside the existing meta observation loop — same `@ObservationIgnored` task + `deinit` cancel convention; resolve `accountId` the same way the meta observation does). Add:

```swift
    func toggleNotify(_ item: MetaCommunityListItem) {
        Haptics.tap()
        Task { [weak self] in
            guard let self else { return }
            do {
                if notifyingCommunityIds.contains(item.id) {
                    try await accountScope.reminderService.removeCommunityFollow(communityServerId: item.id)
                } else {
                    try await accountScope.reminderService.setCommunityFollow(
                        communityServerId: item.id,
                        communityActorId: item.communityActorId,
                        name: item.name,
                        title: item.title ?? item.name,
                        instanceHost: instanceHost,   // the VM's existing About-section host
                        iconUrl: item.iconUrl?.absoluteString
                    )
                }
            } catch {
                logger.error("toggleNotify failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
```

Verify in place the VM's actual property names for the account scope and the About-section instance host (it passes one to `observeMetaCommunities(forAccountId:instanceHost:)`), and whether `MetaCommunityListItem.iconUrl` is `URL?` or `String?` — adjust the conversion accordingly. No toast (the adjacent Favourite star shows none either — row buttons give haptic + visual state only).

- [ ] **Step 2: Row bell.** In `MetaCommunityAboutRow`, add props `let isNotifying: Bool; let onNotify: () -> Void` and, between the Favourite star button and the subscribe pill, a borderless bell button following the star's exact styling pattern:

```swift
            Button(action: onNotify) {
                Image(systemName: CommunityNotifyLabel.symbol(isNotifying: isNotifying))
                    .foregroundStyle(isNotifying ? Color.accentColor : Color(.tertiaryLabel))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                isNotifying
                    ? Text("Stop notifying about new posts", comment: "Accessibility label to remove a community new-posts follow")
                    : Text("Notify about new posts", comment: "Accessibility label to follow a community for new-post notifications")
            )
```

Wire all four `MetaCommunityAboutRow(...)` construction sites in `SubscriptionsView` (high-confidence + disclosure group) with `isNotifying: viewModel.notifyingCommunityIds.contains(item.id)` and `onNotify: { viewModel.toggleNotify(item) }`. The bell shows signed-in AND signed-out (follows are local; only Subscribe is sign-in gated).

- [ ] **Step 3: Subscribed-list context menu.** In the `Section("Subscribed communities")` rows' `.contextMenu`, add after the Open button:

```swift
                                Button {
                                    viewModel.toggleNotify(for: community)
                                } label: {
                                    Label(CommunityNotifyLabel.title,
                                          systemImage: CommunityNotifyLabel.symbol(isNotifying: viewModel.isNotifying(community)))
                                }
```

This needs the row's community SERVER id: check `SubscriptionsCommunityRow`'s fields — if it lacks the server community id, extend the row struct and its producing query (it already joins the `community` table, which has `communityId`) rather than resolving per-tap. Add the matching `toggleNotify(for row:)`/`isNotifying(_ row:)` VM overloads reusing the same service calls (title: the row's display name; actorId: `row.communityActorId`; instance host parsed from the actor id's URL host).

- [ ] **Step 4: VM tests.** Toggle-on inserts a follow row (in-memory DB assert via `reminderSync`), toggle-off removes it; `notifyingCommunityIds` reflects the observation after a set (use the suite's existing async-stream settle pattern).

- [ ] **Step 5: Run SpudTests, format, commit.**

```bash
mint run swiftformat Spud/ SpudTests/
git add <files> && git commit -m "feat: new-posts bell on meta rows and subscribed-list menu"
```

---

### Task 7: Block interplay, feature docs, final sweep

**Files:**
- Modify: the community block call sites (grep `blockCommunity` under `Spud/` — expected: `SearchViewController`'s host method + `CommunityViewController`'s block action; add the follow-removal beside the block call, not inside `LemmyService`)
- Modify: `docs/features/reminders.md`, `docs/features/instance-meta-communities.md`, `docs/features/inbox.md`, `docs/features/community-screen.md`, `docs/features/subscribe-unsubscribe.md`, the search context-menus feature doc, `docs/features/README.md` (BOTH the capability table AND the "Feature coverage by area" map)

**Interfaces:**
- Consumes: `removeCommunityFollow(communityServerId:)`.

- [ ] **Step 1: Block removes the follow.** At each UI block call site, after the block succeeds, fire-and-forget `try? await accountScope.reminderService.removeCommunityFollow(communityServerId: ...)` with a one-line why-comment ("blocking is an explicit 'never show me this' — a live new-posts follow must not keep notifying"). Unit-test at whichever seam the block flow already tests (if none exists, cover via a `ReminderService`-level test asserting remove-after-set leaves no active kinds, and rely on review for the call-site wiring).

- [ ] **Step 2: Feature docs.** Update per the spec's "Docs to update" section. Key edits: `reminders.md` gains the community follow as a third follow type (entry points, >=1 rule, batched notification, mute-pause behavior, block removal, watermark honesty note, Given/When/Then scenarios: follow from the community overflow / a meta row bell; poll fires on one new post; unmute batch; swipe-remove) and its `Not supported` keeps the best-effort-delivery honesty; `instance-meta-communities.md` REMOVES the "No push notification on new posts" out-of-scope claim and documents the bell as the third row action; `README.md`'s by-area map line for meta communities loses its "no push notification on new posts" caveat. `Surfaces:` unions stay `iphone`, `ipad`. No `.swift` links.

- [ ] **Step 3: Full verify.** `mint run swiftformat .` (then re-check `git status -u` for unexpected rewrites), `make test` (full plan; known flakes: one real-network SpudDataKitTests test offline-flake, VM `CancellationError` parallelism flakes — isolate-and-rerun before judging red), `make snapshot` on the reference sim. Expected: green.

- [ ] **Step 4: Commit docs + block interplay.**

```bash
git add <files> && git commit -m "feat: block removes community follow; document new-posts follows"
```

---

## Execution notes

- Worktree: create with `git worktree add -b feat/community-new-posts-follow <path> main` from the main checkout (EnterWorktree bases on origin/main, which is behind — don't use its default base). Run `make project` in the worktree before first build.
- Merge-back: re-check `main..feat/community-new-posts-follow` overlap right before merging (shared checkout; local main moves). Run `git annex restage` first if merging in the shared checkout.
- Snapshot recording (Task 4) must happen on the booted reference iPhone 17 Pro sim; keep exactly one sim booted.
