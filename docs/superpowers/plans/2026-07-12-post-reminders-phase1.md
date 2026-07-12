# Post Reminders — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship time-based ("remind me later") reminders on a whole post — set from a "Remind Me…" menu, delivered as a reliable OS local notification, and surfaced in a new Inbox "Reminders" segment with a fired-unseen badge.

**Architecture:** A durable per-account `reminder` GRDB table (`v35`) is the source of truth. A `ReminderService` (SpudDataKit) creates/removes reminders and drives an injected `ReminderNotificationScheduling` protocol (UNUserNotificationCenter-backed) to schedule/cancel OS notifications; on launch/foreground it reconciles overdue reminders to `fired`. The app wires the notification-tap delegate into the existing `AppCoordinator.open` deep-link funnel, adds a "Remind Me…" submenu (mirroring `MuteDuration`), and adds a `.reminders` case to the Inbox's existing `InboxScope` segmented control, rendering the durable table with a badge.

**Tech stack:** Swift 6 (strict concurrency), UIKit, GRDB, `UserNotifications`, Swift Testing. Scope of THIS plan is Phase 1 of the spec (`docs/superpowers/specs/2026-07-12-post-reminders-design.md` §9.1); activity/poll/subtree/background are later plans.

## Global Constraints

- Spec is authoritative: `docs/superpowers/specs/2026-07-12-post-reminders-design.md`. Phase 1 = time reminders on a whole post + Inbox segment only. Do NOT build activity triggers, polling, `BGAppRefreshTask`, or comment-subtree scope (later phases) — but leave the schema/interfaces ready for them.
- Terminology (exact, everywhere): action **"Remind Me…"**; list/segment **"Reminders"**. No emojis anywhere.
- Whole-post target uses the sentinel **`rootCommentServerId = 0`** (SQLite treats NULLs as distinct in a UNIQUE index). `kind = "time"` for Phase 1.
- Time-preset dates (spec §2.4): In 3 hours = now+3h; This evening = today 18:00 (if now ≥ 17:00 → now+3h); Tomorrow = tomorrow 09:00; In 2 days = +2d 09:00; In a week = +7d 09:00; Pick a time… = user-chosen, reject past.
- Native-iOS bar: HIG, SF Symbols, Dynamic Type, light/dark, VoiceOver, iPhone + iPad both first-class. `@Observable` VMs, AsyncSequence/Observation (no Combine/Core Data). Per-account flows take an `AccountScope`.
- Swift Testing unit tests (`struct` suites, `@Test`, `#expect`, explicit `import Foundation`). After a change to a VC's `Dependencies`, build the test targets (missed doubles are LINKER errors).
- GRDB date convention: `*Record` Codable date columns store ISO-8601 TEXT — bind a `Date` in SQL, never an epoch double (a Double-vs-text `<= ?` is silently always-false). New migration is the next case, never edit an existing one.
- Docs: new `docs/features/reminders.md` + README capability table + by-area map (folded into the task whose deliverable is user-visible).
- Worktree `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/post-reminders` (branch `feat/post-reminders`). Stage explicit paths. Commit trailers:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY`. Run `make project` after adding files; verify with `make build` + the relevant `make test-only ONLY=<target>`.

## File structure

| File | Responsibility |
|---|---|
| `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (modify) | Add `v35_reminder` |
| `SpudDataKit/Services/AppDatabase/Records/ReminderRecord.swift` (create) | GRDB record for the `reminder` table |
| `SpudDataKit/Services/AppDatabase/ReminderWrites.swift` (create) | upsert / remove / markFired / markSeen / reconcileOverdue writes |
| `SpudDataKit/Services/AppDatabase/ReminderQueries.swift` (create) | sync reads: overdue-time select, unseen count, one-shot list |
| `SpudDataKit/Services/AppDatabase/ReminderObservations.swift` (create) | `AsyncStream<[ReminderListRow]>` for the segment + unseen-count stream |
| `SpudDataKit/Services/Reminders/ReminderNotificationScheduling.swift` (create) | protocol + `UNUserNotificationCenter` impl + content/URL builder |
| `SpudDataKit/Services/Reminders/ReminderService.swift` (create) | per-account actor: create/remove time reminders, reconcile overdue |
| `Spud/Reminders/ReminderPreset.swift` (create) | pure preset enum + `resolvedDate(now:calendar:)` |
| `Spud/Reminders/RemindMeMenu.swift` (create) | pure menu-model builder (items + checkmarks) |
| `Spud/App/AppDelegate.swift` (modify) | set `UNUserNotificationCenter.delegate`; route taps to `AppCoordinator` |
| `Spud/Scenes/PostDetail/Content/PostDetailViewController+OverflowMenu.swift` (modify) | "Remind Me…" submenu (whole post) |
| `Spud/Scenes/PostList/PostListViewController.swift` (modify) | "Remind Me…" submenu in the feed cell context menu |
| `Spud/Scenes/Inbox/InboxScope.swift` (modify) | add `.reminders` case + title |
| `Spud/Scenes/Inbox/InboxViewModel.swift` / `InboxViewController.swift` / `InboxCells.swift` (modify) | render the Reminders segment from the durable table; open/remove; mark seen |
| `SpudDataKit/Services/Inbox/UnreadCountService.swift` (modify) | blend fired-unseen reminder count into the badge |
| `Spud/Services/Preferences/PreferencesService.swift` (modify) | `reminderNotificationsEnabled` toggle |
| `docs/features/reminders.md` (create) | feature doc |

---

### Task 1: `v35_reminder` migration + `ReminderRecord`

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (after `v34_postCrossPost`)
- Create: `SpudDataKit/Services/AppDatabase/Records/ReminderRecord.swift`
- Test: `SpudDataKitTests/AppDatabase/ReminderRecordTests.swift`

**Interfaces — Produces:**
```swift
public struct ReminderRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var accountId: Int64
    public var postServerId: Int64
    public var apId: String                    // denormalized post permalink; opens without the (evictable) post row
    public var rootCommentServerId: Int64      // 0 == whole post (sentinel)
    public var kind: String                    // "time" (Phase 1) | "activity" (later)
    public var fireAt: Date?
    public var nextCheckAt: Date?              // activity only (nil in Phase 1)
    public var baselineCount: Int64?           // activity only
    public var baselineAt: Date?               // activity only
    public var lastNotifiedAt: Date?
    public var status: String                  // "scheduled" | "fired" | "dismissed" | "failed"
    public var unseen: Bool
    public var notificationRequestId: String?
    public var titleSnapshot: String
    public var communityName: String
    public var instanceHost: String
    public var thumbnailUrl: String?
    public var createdAt: Date
    public static let databaseTableName = "reminder"
}
public extension ReminderRecord {
    static let wholePostSentinel: Int64 = 0
    enum Kind: String { case time, activity }
    enum Status: String { case scheduled, fired, dismissed, failed }
}
```

- [ ] **Write tests** (`ReminderRecordTests`): (a) after `AppDatabase.inMemory()`, inserting a `ReminderRecord` and fetching by id round-trips every field incl. `fireAt` (assert Date equality to the second); (b) two inserts with the SAME `(accountId, postServerId, rootCommentServerId=0, kind="time")` — the second `insert` throws a unique-constraint error (proves the sentinel-based unique index works where NULL would not); (c) two inserts differing only by `kind` ("time" vs "activity") both succeed. Follow `CrossPostTests`/`AppDatabaseTests` patterns for `inMemory()` + `writer.write`.
- [ ] **Implement** the record + migration. Migration `v35_reminder`:
  ```swift
  migrator.registerMigration("v35_reminder") { db in
      try db.create(table: "reminder") { t in
          t.autoIncrementedPrimaryKey("id")
          t.column("accountId", .integer).notNull().indexed()
          t.column("postServerId", .integer).notNull()
          t.column("apId", .text).notNull()
          t.column("rootCommentServerId", .integer).notNull().defaults(to: 0) // 0 = whole post
          t.column("kind", .text).notNull()
          t.column("fireAt", .datetime)
          t.column("nextCheckAt", .datetime)
          t.column("baselineCount", .integer)
          t.column("baselineAt", .datetime)
          t.column("lastNotifiedAt", .datetime)
          t.column("status", .text).notNull()
          t.column("unseen", .boolean).notNull().defaults(to: false)
          t.column("notificationRequestId", .text)
          t.column("titleSnapshot", .text).notNull()
          t.column("communityName", .text).notNull()
          t.column("instanceHost", .text).notNull()
          t.column("thumbnailUrl", .text)
          t.column("createdAt", .datetime).notNull()
          t.uniqueKey(["accountId", "postServerId", "rootCommentServerId", "kind"])
      }
      try db.create(index: "index_reminder_on_fireAt", on: "reminder", columns: ["fireAt"])
  }
  ```
  Add `"reminder"` to the canonical table-set assertion in `AppDatabaseTests` if one exists (grep for the existing table list).
- [ ] **Verify** `make test-only ONLY=SpudDataKitTests` green (build test target too). **Commit** (`feat: add v35_reminder migration + ReminderRecord`).

---

### Task 2: Reminder writes + queries + observations

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/ReminderWrites.swift`, `ReminderQueries.swift`, `ReminderObservations.swift`
- Test: `SpudDataKitTests/AppDatabase/ReminderWritesTests.swift`

**Interfaces — Consumes:** `ReminderRecord` (Task 1). **Produces** (on `AppDatabase`):
```swift
// Writes (async, on writer)
func upsertReminder(_ record: ReminderRecord) async throws -> Int64          // returns row id; upsert by unique key
func removeReminder(accountId: Int64, postServerId: Int64, rootCommentServerId: Int64, kind: String) async throws -> String?  // returns the removed row's notificationRequestId (to cancel), or nil
func markReminderFired(id: Int64, firedAt: Date) async throws               // status=fired, unseen=true, lastNotifiedAt=firedAt
func markRemindersSeen(accountId: Int64) async throws                       // unseen=false for all fired reminders of the account
func reconcileOverdueTimeReminders(accountId: Int64, asOf: Date) async throws -> [ReminderRecord]  // fireAt<=asOf && kind=time && status=scheduled -> mark fired+unseen; return the ones flipped
// Sync reads (nonisolated)
func reminderSync(accountId: Int64, postServerId: Int64, rootCommentServerId: Int64, kind: String) -> ReminderRecord?
func activeReminderKindsSync(accountId: Int64, postServerId: Int64, rootCommentServerId: Int64) -> Set<String>  // which kinds have a live reminder (for menu checkmarks)
func unseenReminderCountSync(accountId: Int64) -> Int
// Observations
func observeReminderList(accountId: Int64) -> AsyncStream<[ReminderListRow]>  // ordered: fired-unseen first, then scheduled by fireAt asc
func observeUnseenReminderCount(accountId: Int64) -> AsyncStream<Int>
```
`ReminderListRow` (a Sendable read-model in `ReminderObservations.swift`): `id, postServerId, apId, rootCommentServerId, kind, status, unseen, fireAt, titleSnapshot, communityName, instanceHost, thumbnailUrl`. `apId` is the denormalized permalink from `ReminderRecord` (Task 1), so opening a reminder never needs the (possibly-evicted) `post` row.

- [ ] **Write tests** (`ReminderWritesTests`, `inMemory()`): upsert then `reminderSync` returns it; upsert same unique key twice → one row, updated fields; `removeReminder` deletes + returns the stored `notificationRequestId`; `markReminderFired` sets status/unseen/lastNotifiedAt; `markRemindersSeen` clears unseen; `reconcileOverdueTimeReminders` flips only `fireAt<=asOf & scheduled & time` rows and returns them (a future `fireAt` and an `activity` row are untouched); `unseenReminderCountSync` counts fired-unseen; `activeReminderKindsSync` returns the live kinds.
- [ ] **Implement** the three files (mirror `DiagnosticEventWrites`/`CrossPostQueries`/`*Observations` styles; observations pass `.async(onQueue: .global(qos: .userInitiated))`). Bind `Date` args directly in SQL.
- [ ] **Verify** `make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: reminder writes, queries, observations`).

---

### Task 3: `ReminderPreset` (pure time-preset resolution)

**Files:**
- Create: `Spud/Reminders/ReminderPreset.swift`
- Test: `SpudTests/Reminders/ReminderPresetTests.swift`

**Interfaces — Produces:**
```swift
enum ReminderPreset: CaseIterable {
    case inThreeHours, thisEvening, tomorrow, inTwoDays, inAWeek
    var menuTitle: String { /* "In 3 hours", "This evening", ... (localized) */ }
    /// Resolves to an absolute fire date. `thisEvening` returns today 18:00 unless
    /// `now` is already >= 17:00, in which case it returns `now + 3h` (never a past/imminent fire).
    func resolvedDate(now: Date, calendar: Calendar) -> Date
}
/// Validates a user-picked custom date: returns it iff strictly in the future.
func validCustomReminderDate(_ date: Date, now: Date) -> Date?
```

- [ ] **Write tests** (`ReminderPresetTests`, inject a fixed `now` + `Calendar(identifier: .gregorian)` with a fixed timezone): `.inThreeHours` == now+3h; `.tomorrow` == next day 09:00; `.inTwoDays`/`.inAWeek` == +2d/+7d at 09:00; `.thisEvening` with now=10:00 → today 18:00; `.thisEvening` with now=19:00 → now+3h (22:00); every preset resolves strictly after `now`; `validCustomReminderDate(past)` == nil, `(future)` == the date.
- [ ] **Implement** using `Calendar.date(bySettingHour:minute:second:of:)` / `date(byAdding:)`. No `Date()`/`Calendar.current` inside the pure functions — take them as params (the caller passes `Date()`/`.current`).
- [ ] **Verify** `make test-only ONLY=SpudTests`. **Commit** (`feat: reminder time-preset resolution`).

---

### Task 4: Notification layer (content builder + scheduling protocol + delegate + permission + toggle)

**Files:**
- Create: `SpudDataKit/Services/Reminders/ReminderNotificationScheduling.swift`
- Modify: `Spud/App/AppDelegate.swift`, `Spud/Services/Preferences/PreferencesService.swift`
- Test: `SpudTests/Reminders/ReminderNotificationContentTests.swift`

**Interfaces — Produces:**
```swift
public struct ReminderNotificationContent: Sendable, Equatable {
    public let title: String        // titleSnapshot
    public let body: String         // e.g. "c/news@example.com · Tap to revisit"
    public let routingURLString: String  // URL.SpudInternalLink.objectAtURL(url: apId).url.absoluteString
}
public enum ReminderNotificationFactory {
    /// Pure. Builds the notification content + the deep-link userInfo for a fired time reminder.
    public static func timeReminderContent(titleSnapshot: String, communityName: String,
                                           instanceHost: String, apId: String) -> ReminderNotificationContent
}
public protocol ReminderNotificationScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func authorizationGranted() async -> Bool
    func schedule(requestId: String, fireAt: Date, content: ReminderNotificationContent) async
    func cancel(requestId: String) async
}
public final class UNReminderNotificationScheduler: ReminderNotificationScheduling { /* UNUserNotificationCenter impl */ }
```
- `schedule` builds a `UNMutableNotificationContent` (title/body, `userInfo["spudRoutingURL"] = content.routingURLString`), a `UNCalendarNotificationTrigger` from `fireAt` (via `Calendar.dateComponents`), and adds a `UNNotificationRequest(identifier: requestId, ...)`. `cancel` calls `removePendingNotificationRequests(withIdentifiers:)`.
- **`AppDelegate`:** in `didFinishLaunching`, set `UNUserNotificationCenter.current().delegate`. Implement `userNotificationCenter(_:didReceive:completionHandler:)` — read `response.notification.request.content.userInfo["spudRoutingURL"]`, build a `URL`, and call `AppCoordinator.shared.open(url, in: <mainWindow>)` (find how AppDelegate/SceneDelegate reaches the active `MainWindow` — mirror `SceneDelegate.scene(_:openURLContexts:)` at `SceneDelegate.swift:119`). Implement `willPresent` → `[.banner, .list, .sound]` so a reminder shows even in-foreground.
- **`PreferencesService`:** add `reminderNotificationsEnabled: Bool = true` (`@UserDefaultsBacked`, mirror an existing bool pref) + its `*Stream`.

- [ ] **Write tests** (`ReminderNotificationContentTests`): `ReminderNotificationFactory.timeReminderContent(...)` → `title == titleSnapshot`; `body` contains `c/<communityName>@<instanceHost>`; `routingURLString == URL.SpudInternalLink.objectAtURL(url: URL(string: apId)!).url.absoluteString`. (Pure — no UN.)
- [ ] **Implement** the content builder + scheduler protocol/impl + AppDelegate delegate + preference. (The `UN*` glue and the delegate are not unit-tested — covered by the pure builder + on-device.)
- [ ] **Verify** `make project && make build && make test-only ONLY=SpudTests`. **Commit** (`feat: reminder notification layer + tap routing`).

---

### Task 5: `ReminderService` (per-account) — create/remove time reminders + reconcile

**Files:**
- Create: `SpudDataKit/Services/Reminders/ReminderService.swift`
- Test: `SpudDataKitTests/Reminders/ReminderServiceTests.swift`

**Interfaces — Consumes:** `AppDatabase` reminder writes (Task 2), `ReminderNotificationScheduling` (Task 4). **Produces:**
```swift
public actor ReminderService {
    init(accountId: Int64, appDatabase: AppDatabase, scheduler: ReminderNotificationScheduling)
    /// Upserts a time reminder for the whole post, schedules the OS notification (requesting
    /// permission on first use), and returns the stored record. requestId = a stable string
    /// e.g. "reminder-\(accountId)-\(postServerId)-0-time".
    func setTimeReminder(postServerId: Int64, apId: String, fireAt: Date,
                         titleSnapshot: String, communityName: String,
                         instanceHost: String, thumbnailUrl: String?) async throws
    func removeTimeReminder(postServerId: Int64) async throws   // deletes row + cancels the OS request
    /// Marks overdue time reminders fired+unseen (badge) — call on launch/foreground.
    func reconcileOverdue(asOf: Date) async throws
}
```
- `setTimeReminder`: request authorization if not yet granted (respect `reminderNotificationsEnabled`); upsert the record (`kind=time`, `status=scheduled`, `notificationRequestId=<stable id>`); call `scheduler.schedule(...)` with `ReminderNotificationFactory.timeReminderContent(...)`. If permission denied, still persist the record (in-app only) — do NOT fail.
- `removeTimeReminder`: `appDatabase.removeReminder(...)` → cancel the returned `notificationRequestId` via `scheduler.cancel`.
- `reconcileOverdue`: `appDatabase.reconcileOverdueTimeReminders(accountId:asOf:)`.

- [ ] **Write tests** (`ReminderServiceTests`) with a **fake `ReminderNotificationScheduling`** (records schedule/cancel calls, returns granted=true): `setTimeReminder` persists a `scheduled` record AND calls `scheduler.schedule` with the matching id/fireAt/content; a second `setTimeReminder` for the same post replaces (one row, scheduler re-scheduled); `removeTimeReminder` deletes the row AND calls `scheduler.cancel` with the stored id; permission-denied fake (granted=false) → record still persisted, no crash; `reconcileOverdue(asOf: future)` flips a past `scheduled` reminder to `fired/unseen`. Use `AppDatabase.inMemory()`.
- [ ] **Implement** the actor.
- [ ] **Verify** `make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: ReminderService time reminders + reconcile`).

**Wiring note (do in this task):** construct/expose `ReminderService` per account off the DI graph the way other per-account services are reached (grep how `AccountScope`/`DependencyContainer` vends `lemmyService`/`outboxService`); call `reconcileOverdue(asOf: Date())` on launch + foreground (mirror where Spotlight reindex fires — `MainWindow.applyDefaultAccount` + `SceneDelegate.sceneWillEnterForeground`).

---

### Task 6: "Remind Me…" menu (whole post) — post detail + feed

**Files:**
- Create: `Spud/Reminders/RemindMeMenu.swift` (pure menu model)
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController+OverflowMenu.swift`, `Spud/Scenes/PostList/PostListViewController.swift`
- Test: `SpudTests/Reminders/RemindMeMenuTests.swift`

**Interfaces — Consumes:** `ReminderPreset` (T3), `activeReminderKindsSync` (T2), `ReminderService` (T5). **Produces:**
```swift
enum RemindMeMenuItem: Equatable {
    case preset(ReminderPreset)
    case customTime
    // (activity item added in Phase 2)
}
enum RemindMeMenu {
    /// The ordered items + which are currently active (checkmarked). `hasTimeReminder`
    /// drives whether the presets show as "set" — in Phase 1, an active time reminder
    /// checkmarks nothing per-preset (we don't store which preset), so `hasTimeReminder`
    /// instead surfaces a single "Cancel reminder" affordance.
    static func items() -> [RemindMeMenuItem]  // presets in spec order + customTime
}
```
- UIKit: build a `UIMenu` titled "Remind Me" (SF Symbol `bell` / `alarm`) with a `UIAction` per preset → `Task { try await reminderService.setTimeReminder(...) }` using `preset.resolvedDate(now: Date(), calendar: .current)` + the post's denormalized fields; a "Pick a time…" action → present a `UIDatePicker` sheet → `validCustomReminderDate`; and, when `activeReminderKindsSync` shows a live `time` reminder, a destructive "Cancel reminder" action → `removeTimeReminder`. Show a confirmation toast (reuse the app's existing toast/`displayPending`-style helper). Mirror `makeMuteCommunityMenu` (`PostDetailViewController+OverflowMenu.swift:147`) and the feed's `MuteDuration` submenu (`PostListViewController.swift:1799`).
- Add the submenu into `makePostOverflowMenu()` and the feed `contextMenuConfigurationForRowAt` groups.

- [ ] **Write tests** (`RemindMeMenuTests`): `RemindMeMenu.items()` returns the 5 presets in spec order followed by `.customTime`; (pure model only — the `UIMenu`/VC wiring is exercised by build + the reviewer).
- [ ] **Implement** the pure model + both menu wirings + toast.
- [ ] **Verify** `make project && make build && make test-only ONLY=SpudTests`. **Commit** (`feat: Remind Me menu on post detail + feed`).

---

### Task 7: Inbox "Reminders" segment + badge + docs

**Files:**
- Modify: `Spud/Scenes/Inbox/InboxScope.swift`, `InboxViewModel.swift`, `InboxViewController.swift`, `InboxCells.swift`, `SpudDataKit/Services/Inbox/UnreadCountService.swift`
- Create: `docs/features/reminders.md`
- Test: `SpudDataKitTests` (badge query) + `SpudSnapshotTests/RemindersSegmentSnapshotTests.swift`

**Interfaces — Consumes:** `observeReminderList` / `observeUnseenReminderCount` / `markRemindersSeen` (T2), `removeTimeReminder` (T5), `AppCoordinator` routing.

- **`InboxScope`:** add `case reminders` (after `.mentions`) + its `title` "Reminders". (This grows the segmented control automatically — `InboxScope.allCases`.)
- **`InboxViewModel`:** when `scope == .reminders`, drive rows from `appDatabase.observeReminderList(accountId:)` (durable GRDB observation) instead of the server fetch used by replies/mentions; expose `[ReminderListRow]`. On entering the segment, call `markRemindersSeen(accountId:)` (clears the badge). Swipe-to-remove calls `reminderService.removeTimeReminder(postServerId:)`.
- **`InboxViewController` / `InboxCells`:** a reminder cell showing thumbnail + title + community + a status line ("in 2 days" via a relative formatter / "fired · tap to revisit"). Row tap → build `URL.SpudInternalLink.objectAtURL(url: apId)` → `AppCoordinator.shared.open(...)`. Dynamic Type, light/dark, VoiceOver label ("Reminder: <title>, <status>"), iPad.
- **`UnreadCountService`:** blend `unseenReminderCountSync(accountId:)` (or the observation) into the badge total so a fired reminder lights the Inbox tab. Keep the reminder segment's own view of "unseen" driving the mark-seen clear. (Read the current `unreadCount` computation and add the reminder unseen count to the displayed total; a fresh account → 0.)

- [ ] **Write tests:** (SpudDataKitTests) a fired-unseen reminder makes `unseenReminderCountSync` == 1 and after `markRemindersSeen` == 0; `observeReminderList` orders fired-unseen before scheduled. (SpudSnapshotTests) `RemindersSegmentSnapshotTests` renders the segment cell(s) for empty / one-scheduled / one-fired states, light+dark, on the reference device (record → verify per `SpudSnapshotTests/CLAUDE.md`).
- [ ] **Implement** the segment + badge blend + `docs/features/reminders.md` (Given/When/Then per spec §10, Phase-1 scope: set/cancel a time reminder; it fires → notification + Inbox segment + badge; notifications-denied degradation) + README capability table + by-area map.
- [ ] **Verify** `make project && make build && make test-only ONLY=SpudDataKitTests && make test-only ONLY=SpudTests`; record the snapshot class. **Commit** (`feat: Inbox Reminders segment + badge` and a `docs:` commit).

---

## Notes for the executor

- Build the **test targets** after Task 4/5/7 (Dependencies/service changes surface as LINKER errors only when tests build). SourceKit "No such module" squiggles are unreliable here — trust `make build`.
- This is a fresh worktree: its snapshot refs are unmaterialized annex pointers — materialize before any snapshot run (see `SpudSnapshotTests/CLAUDE.md`).
- Leave `nextCheckAt`/`baselineCount`/`baselineAt` columns + the `activity` kind unused in Phase 1 but present, so Phase 2 adds no migration.
