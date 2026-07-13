# Post Reminders — Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the activity-based follow ("notify me as the discussion grows") on a **whole post**: a "When there are new comments" menu item that watches the post's comment count via a foreground poll and fires a notification on the smart rule, surfaced in the Inbox Reminders segment.

**Architecture:** Reuses the Phase-1 `reminder` table (the reserved `activity` kind + `baselineCount`/`baselineAt`/`nextCheckAt` columns — no migration). `ReminderService` gains `setActivityReminder`/`removeActivityReminder` and `pollDueActivityReminders(commentCountFetcher:)`; the fetcher (built by `SchedulerService` from the account's `LemmyService`) refreshes the post and reads its comment count. A new sweep in `SchedulerService.tick()` (the existing foreground 5-min Timer) drives the poll, throttled per-follow. Fire → activity notification + `markFired`/unseen + re-arm baseline. Background polling (`BGAppRefreshTask`) is Phase 4, NOT here.

**Tech stack:** Swift 6 strict concurrency, GRDB, `UserNotifications`, UIKit, Swift Testing. Spec: `docs/superpowers/specs/2026-07-12-post-reminders-design.md` (§3 rule, §5.1/§5.3 poll, §9.2 phase). Phase 1 is merged (base of this branch).

## Global Constraints

- Phase 2 = whole-post **activity** reminders + the foreground poll ONLY. NO comment-subtree (Phase 3), NO `BGAppRefreshTask`/background mode (Phase 4). Reuse the Phase-1 `reminder` table/columns — **no new migration**.
- **Smart rule (spec §3, fixed — no user knobs):** with `new = commentsNow - baselineCount`, `elapsed = now - baselineAt`, fire when `new >= 5 OR (new >= 1 AND elapsed >= 24h)`. On fire: notify, `unseen = true`, and re-arm (`baselineCount = commentsNow`, `baselineAt = now`). The `5` and `24h` constants live in ONE place (`ReminderActivityRule`).
- **Poll throttle:** a followed post is re-polled at most every ~30 min (`nextCheckAt = now + pollInterval`, `pollInterval = 30 * 60`), centralized. Only due follows (`nextCheckAt <= now`) are polled.
- **Whole-post count** = `PostRecord.numberOfComments`, refreshed by the account's `LemmyService.fetchPostInfo(serverPostId:)` (a `getPost`); read back via a sync query. Comment-count source per CLAUDE.md: only a full `PostView` import updates `numberOfComments`.
- Terminology: the activity menu item is **"When there are new comments"** (never "Follow"/"Watch" in copy). Consistent with Phase 1's "Remind Me…" umbrella. No emojis.
- Native-iOS bar; Swift 6 strict concurrency (`ReminderService` is an actor; the fetcher closure is `@Sendable`); Swift Testing. GRDB date columns bind a `Date` (not epoch). After DI/Dependencies changes, build the test targets.
- Docs: extend `docs/features/reminders.md` (Phase-1 → Phase-2 status) + README table/by-area map.
- Worktree `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/post-reminders-p2` (branch `feat/post-reminders-p2`). Stage explicit paths. Commit trailers:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY`. `make project` after adding files; verify with `make build` + relevant `make test-only`.

## File structure

| File | Responsibility |
|---|---|
| `Spud/Reminders/ReminderActivityRule.swift` (create) | pure fire-rule + constants |
| `SpudDataKit/Services/AppDatabase/ReminderWrites.swift` (modify) | `rearmActivityReminder`, `bumpActivityNextCheck` writes |
| `SpudDataKit/Services/AppDatabase/ReminderQueries.swift` (modify) | `dueActivityRemindersSync`, `postNumberOfCommentsSync` reads |
| `SpudDataKit/Services/Reminders/ReminderService.swift` (modify) | `setActivityReminder`/`removeActivityReminder`/`pollDueActivityReminders` |
| `SpudDataKit/Services/Reminders/ReminderNotificationScheduling.swift` (modify) | `ReminderNotificationFactory.activityReminderContent` |
| `SpudDataKit/Services/Scheduler/SchedulerService.swift` (modify) | `pollActivityRemindersSweep()` added to `tick()` |
| `Spud/Reminders/PostReminderDispatching.swift` (modify) | "When there are new comments" menu item |
| `Spud/Scenes/Inbox/InboxCells.swift` (modify) | activity reminder status line ("Watching" / "Watching · N new") |
| `docs/features/reminders.md` (modify) | Phase-2 status + scenarios |

---

### Task 1: Activity fire-rule + activity reminder create/remove

**Files:**
- Create: `Spud/Reminders/ReminderActivityRule.swift`; Test: `SpudTests/Reminders/ReminderActivityRuleTests.swift`
- Modify: `SpudDataKit/Services/Reminders/ReminderService.swift`; Test: `SpudDataKitTests/Reminders/ReminderServiceActivityTests.swift`

**Interfaces — Produces:**
```swift
enum ReminderActivityRule {
    static let newCommentThreshold = 5
    static let fallbackInterval: TimeInterval = 24 * 60 * 60
    static let pollInterval: TimeInterval = 30 * 60
    /// Fire when >= threshold new, OR (>=1 new AND >= fallback elapsed).
    static func shouldFire(newComments: Int, elapsed: TimeInterval) -> Bool
}
// on ReminderService (actor):
func setActivityReminder(postServerId: Int64, apId: String, baselineCount: Int64,
                         titleSnapshot: String, communityName: String,
                         instanceHost: String, thumbnailUrl: String?) async throws
func removeActivityReminder(postServerId: Int64) async throws
```
- `setActivityReminder`: request authorization if not granted (respect `reminderNotificationsEnabled`, like `setTimeReminder`, but do NOT throw on denial — persist anyway); upsert a row `kind=activity`, `status=scheduled`, `baselineCount=<current>`, `baselineAt=Date()`, `nextCheckAt=Date()+ReminderActivityRule.pollInterval`, `notificationRequestId=nil` (activity notifications are posted ad-hoc, not pre-scheduled). Activity reminders schedule NO up-front `UNCalendarNotificationTrigger` (they fire from the poll).
- `removeActivityReminder`: `appDatabase.removeReminder(... kind: activity ...)` (there's no OS request to cancel — `notificationRequestId` is nil).

- [ ] **Write tests:** `ReminderActivityRuleTests` — `shouldFire`: `new=5,elapsed=0` → true; `new=4,elapsed=0` → false; `new=1,elapsed=24h` → true; `new=1,elapsed=23h` → false; `new=0,elapsed=48h` → false (zero never fires). `ReminderServiceActivityTests` (fake scheduler, `inMemory()`): `setActivityReminder` persists a `scheduled` `activity` row with `baselineCount`/`baselineAt`/`nextCheckAt` set and NO scheduler.schedule call; `removeActivityReminder` deletes it.
- [ ] **Implement.** Verify `make test-only ONLY=SpudTests && make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: activity reminder rule + create/remove`).

---

### Task 2: The poll + activity notification + diagnostics

**Files:**
- Modify: `ReminderWrites.swift`, `ReminderQueries.swift`, `ReminderService.swift`, `ReminderNotificationScheduling.swift`
- Test: `SpudDataKitTests/Reminders/ReminderPollTests.swift`

**Interfaces — Produces:**
```swift
// AppDatabase (ReminderQueries/Writes)
func dueActivityRemindersSync(accountId: Int64, asOf: Date) -> [ReminderRecord]   // kind=activity AND status IN (scheduled,fired) AND nextCheckAt <= asOf
func rearmActivityReminder(id: Int64, baselineCount: Int64, baselineAt: Date, nextCheckAt: Date, firedAt: Date) async throws  // fire: status=fired, unseen=true, lastNotifiedAt=firedAt, re-arm baseline + push nextCheckAt
func bumpActivityNextCheck(id: Int64, nextCheckAt: Date) async throws             // no-fire: just push nextCheckAt (keep baseline)
// ReminderNotificationFactory (pure)
static func activityReminderContent(titleSnapshot: String, communityName: String, instanceHost: String, apId: String, newCount: Int) -> ReminderNotificationContent
// ReminderService (actor)
func pollDueActivityReminders(asOf: Date, commentCountFetcher: @Sendable (Int64) async -> Int?) async
```
- `activityReminderContent`: title = titleSnapshot; body = "N new comments · c/<community>@<host>" (pluralize 1 vs N — a `String(format:)` with a positional specifier); routingURL = `objectAtURL(apId)`.
- `pollDueActivityReminders`: for each `dueActivityRemindersSync(accountId:asOf:)` — `commentsNow = await commentCountFetcher(postServerId)`; if nil (fetch failed) → `bumpActivityNextCheck(nextCheckAt: asOf + pollInterval)` and skip (best-effort, no fire; a diagnostic `poll.fetchFailed`). Else `new = Int(commentsNow) - Int(baselineCount)`; if `ReminderActivityRule.shouldFire(newComments: new, elapsed: asOf - baselineAt)` → post the activity notification via `scheduler` (schedule with a fire-now trigger, i.e. a nil/near-immediate `UNTimeIntervalNotificationTrigger` — add a `scheduler.postNow(requestId:content:)` to the protocol, or reuse `schedule` with `fireAt: asOf`), then `rearmActivityReminder(baselineCount: commentsNow, baselineAt: asOf, nextCheckAt: asOf + pollInterval, firedAt: asOf)`; else `bumpActivityNextCheck(nextCheckAt: asOf + pollInterval)`. Emit `.reminder` diagnostics (`poll.fired`, per spec §5.3). Note: `dueActivityRemindersSync` includes already-`fired` rows so a re-armed follow keeps polling.
  - **Add to `ReminderNotificationScheduling`:** `func postNow(requestId: String, content: ReminderNotificationContent) async` (an immediate local notification; the `UNReminderNotificationScheduler` impl uses a `UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)` or `nil` trigger). Keep it distinct from the calendar-scheduled `schedule` used by time reminders.
- Add `.reminder` to the `DiagnosticLog` categories if not already present (grep — Phase 1 may have added it; if not, add it).

- [ ] **Write tests** (`ReminderPollTests`, fake scheduler + `inMemory()`): seed an `activity` row (`baselineCount=10`, `baselineAt`=now-1h, `nextCheckAt`=now-1m); `pollDueActivityReminders(asOf: now, commentCountFetcher: { _ in 16 })` → fires (scheduler.postNow called with "6 new comments"), row re-armed (`baselineCount=16`, new `nextCheckAt`, `status=fired`,`unseen=true`); fetcher returning `11` (new=1, elapsed=1h) → NO fire, `nextCheckAt` bumped, baseline unchanged; fetcher `13` with `baselineAt`=now-25h → fires (24h fallback); fetcher returning `nil` → no fire, `nextCheckAt` bumped; a not-due row (`nextCheckAt`=future) is untouched. `activityReminderContent` pure test (title/body/routingURL, "1 new comment" vs "6 new comments").
- [ ] **Implement.** Verify `make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: activity reminder poll + notification`).

---

### Task 3: Wire the poll into the foreground scheduler

**Files:**
- Modify: `SpudDataKit/Services/Scheduler/SchedulerService.swift`
- Test: `SpudDataKitTests/Scheduler/SchedulerActivityPollTests.swift` (if a focused seam is cheap; else rely on Task 2 + build)

**Interfaces — Consumes:** `ReminderService.pollDueActivityReminders` (Task 2), the account's `LemmyService`.

- Add a private `pollActivityRemindersSweep() async` and call it from `tick()` (after the two site-info sweeps, `SchedulerService.swift:120-121`). It iterates the registered accounts (mirror how `fetchSiteInfoAndMyUserInfoForSignedInIfNeeded` enumerates accounts), and for each builds a `commentCountFetcher`:
  ```swift
  let lemmy = accountService.lemmyService(forAccountKeychainId: keychainId)
  let fetcher: @Sendable (Int64) async -> Int? = { postServerId in
      try? await lemmy.fetchPostInfo(serverPostId: Lemmy.PostID(postServerId))   // refreshes numberOfComments
      return appDatabase.postNumberOfCommentsSync(forKeychainId: keychainId, serverPostId: postServerId)
  }
  await accountService.reminderService(forAccountKeychainId: keychainId).pollDueActivityReminders(asOf: now(), commentCountFetcher: fetcher)
  ```
  (`postNumberOfCommentsSync` is a new one-line sync read in `ReminderQueries.swift`/`PostInteractionWrites`-style — add it in Task 2 or here; it reads `PostRecord.numberOfComments` for `(accountId-of-keychainId, postServerId)`.) Wrap the sweep in `.reminder`/`.scheduler` diagnostic bookends. Best-effort; a per-account failure doesn't abort the sweep.
- Because the poll only touches due follows (`nextCheckAt <= now`) and most ticks have none, this is cheap; the 5-min tick × 30-min throttle means each follow is polled ~every 30 min while the app is foregrounded.

- [ ] **Write test (if cheap):** a `SchedulerService` test that with one due activity reminder + a stubbed `LemmyService` (returns a post with more comments), `tick()` results in the reminder firing (row `fired`). If the scheduler's account-enumeration is hard to stub in isolation, SKIP the integration test and note it — Task 2 covers the poll logic; here just ensure `tick()` compiles + the sweep is wired (build-verified).
- [ ] **Implement.** Verify `make project && make build && make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: poll activity reminders in the foreground scheduler`).

---

### Task 4: "When there are new comments" menu item + Inbox status + docs

**Files:**
- Modify: `Spud/Reminders/PostReminderDispatching.swift`, `Spud/Scenes/Inbox/InboxCells.swift`, `docs/features/reminders.md`, `docs/features/README.md`
- Test: `SpudTests/Reminders/` (menu item), `SpudDataKitTests` (status formatting if pure-helper-extracted)

**Interfaces — Consumes:** `ReminderService.setActivityReminder`/`removeActivityReminder` (Task 1), `activeReminderKindsSync` (Phase 1, returns `"activity"` when active), `postNumberOfCommentsSync` (Task 2/3, for the baseline at creation).

- **Menu:** append a **"When there are new comments"** action to the "Remind Me…" submenu in `makeRemindMeMenu` (`PostReminderDispatching.swift`), below the time presets/customTime, with an apt SF Symbol (`bubble.left.and.bubble.right` or `bell.and.waves.left.and.right`). Checkmark it when `activeReminderKindsSync(...).contains(ReminderRecord.Kind.activity.rawValue)`; tapping toggles — set → `setActivityReminder(...)` with `baselineCount = postNumberOfCommentsSync(...) ?? <row's comment count>` and the post's denormalized fields; already-active → `removeActivityReminder(...)`. Confirmation toast ("You'll be notified of new comments" / "Stopped following"). Add `.activity` to the pure `RemindMeMenu.items()` model + its test. Time and activity are independent (a post can have both; each checkmarks separately).
- **Inbox status line:** in the reminder cell (`InboxCells.swift`), for an `activity` reminder render "Watching" when `status=scheduled`, and "Watching · N new" when `status=fired`+`unseen` (N derived from... the row doesn't carry the new-count; simplest: show "New comments" for a fired activity reminder, or store the last-fired new-count — Phase 2 keep it simple: `scheduled` → "Watching for new comments", `fired` → "New comments · tap to catch up"). Keep the time-reminder status lines from Phase 1 unchanged. Update the VoiceOver label accordingly.
- **Docs:** `reminders.md` Status → Phase 2 adds whole-post activity follow; add Given/When/Then (follow a post's comments; poll fires on ≥5 new / 24h; unfollow; the same-loaded-app/foreground-poll limitation stated honestly — background is Phase 4). README table/by-area map.

- [ ] **Write tests:** `RemindMeMenu.items()` now includes `.activityNewComments` (update the Phase-1 test); if you extract a pure Inbox-status formatter, test its `scheduled`/`fired` activity strings.
- [ ] **Implement.** Verify `make project && make build && make test-only ONLY=SpudTests && make test-only ONLY=SpudDataKitTests`. If the Inbox reminder cell's rendered layout changes, re-record `RemindersSegmentSnapshotTests` (fresh worktree: materialize annex pointers first). **Commit** (`feat: follow new comments menu + Inbox status`) + (`docs: reminders phase 2`).

---

## Notes for the executor

- No migration in Phase 2 — the `activity` kind + `baselineCount`/`baselineAt`/`nextCheckAt` columns already exist (Phase 1 v35).
- Build the test targets after Task 1/2/3 (service + scheduler + DI). SourceKit "No such module" squiggles are unreliable — trust `make build`.
- This is a fresh worktree: snapshot refs are unmaterialized annex pointers — materialize before any snapshot run (`SpudSnapshotTests/CLAUDE.md`).
- Background polling (`BGAppRefreshTask`) and comment-subtree scope are explicitly OUT of scope (Phases 3/4).
