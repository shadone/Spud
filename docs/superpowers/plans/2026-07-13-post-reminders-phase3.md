# Post Reminders — Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let a reminder target a **comment subtree** (a specific discussion thread), not just the whole post — both triggers: "Remind me later" (time) and "When there are new comments" (activity, counting only that subtree's replies).

**Architecture:** Reuses the Phase-1/2 `reminder` table's `rootCommentServerId` column (Phase 1 reserved it: `0` = whole post; a comment's server id = that subtree). The activity poll keeps its **count-delta** model — for a subtree the count source is the root comment's server `child_count` (descendant count) instead of the post's `numberOfComments`. `child_count` isn't persisted today, so a small `v36` migration adds it to the `comment` table (populated from the existing `getComments` CommentView). The "Remind Me…" menu is added to the comment long-press context menu; a subtree reminder's notification tap opens the post scrolled to that comment.

**Tech stack:** Swift 6 strict concurrency, GRDB, UserNotifications, UIKit, Swift Testing. Spec: `docs/superpowers/specs/2026-07-12-post-reminders-design.md` (§1 whole-post-OR-subtree, §5.1 subtree count, §9.3). Phases 1+2 merged (base).

## Global Constraints

- Phase 3 = comment-subtree scope for BOTH triggers, on the count-delta model. NO `BGAppRefreshTask` (Phase 4).
- **Subtree identity:** the root comment's stable server id (`rootCommentServerId` on the reminder; `0` stays the whole-post sentinel). A post can carry a whole-post reminder AND subtree reminders on different comments AND multiple-kind reminders — all independent via the unique key `(accountId, postServerId, rootCommentServerId, kind)`.
- **Subtree activity count** = the root comment's server `child_count` (descendant comment count). Baseline at follow = current `child_count`; `new = child_countNow - baselineCount`; same `ReminderActivityRule.shouldFire` + re-arm as whole-post (Phase 2). This deviates from the spec §5.1 timestamp wording in favor of the count-delta model Phase 2 converged on — uniform poll logic. NOTE clearly in the reminders doc that a subtree follow counts *all* new descendants (incl. your own replies), matching whole-post semantics.
- **requestId** must include `rootCommentServerId` so a whole-post and a subtree reminder on the same post get distinct OS notification ids (Phase 1/2 used `reminder-<acct>-<post>-0-<kind>`; generalize the `0` to the actual `rootCommentServerId`).
- **Notification + tap:** a subtree reminder stores the COMMENT's ap_id (`originalCommentUrl`) as its `apId`, so a tap routes via `objectAtURL(commentApId)` → opens the post scrolled to the comment (Comments classify to `.objectAtURL`; `AppCoordinator` already handles `scrollToCommentId`). Its `titleSnapshot`/`communityName`/`instanceHost` stay the POST's (context).
- Terminology: same menu ("Remind Me…"), same items; on a comment they act on the thread. Copy for the subtree activity: "new comments in this thread" / notification "N new replies". No emojis.
- Native-iOS bar; Swift 6; Swift Testing; GRDB date binding; new migration is the NEXT case (`v36`), never edit an existing one. After DI/menu changes, build the test targets.
- Docs: extend `docs/features/reminders.md` (Phase-3) + README table/by-area map.
- Worktree `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/post-reminders-p3` (branch `feat/post-reminders-p3`). Stage explicit paths. Commit trailers:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY`. `make project` after adding files.

## File structure

| File | Responsibility |
|---|---|
| `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (modify) | `v36_commentChildCount` |
| `SpudDataKit/Services/AppDatabase/Records/Comment.swift` (modify) | `childCount` field on `CommentRecord` |
| `SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift` (modify) | populate `childCount` from the CommentView |
| `SpudDataKit/Services/AppDatabase/CommentQueries.swift` or `ReminderQueries.swift` (modify) | `commentChildCountSync(forKeychainId:serverCommentId:)` |
| `SpudDataKit/Services/Reminders/ReminderService.swift` (modify) | `rootCommentServerId` param on set/remove; poll fetcher gains `rootCommentServerId` |
| `SpudDataKit/Services/Reminders/ReminderNotificationScheduling.swift` (modify) | subtree activity content ("N new replies") |
| `SpudDataKit/Services/Scheduler/SchedulerService.swift` (modify) | fetcher branches whole-post vs subtree |
| `SpudDataKit/Services/Lemmy/LemmyService.swift` (modify, if needed) | a subtree comment-count refresh seam |
| `Spud/Reminders/PostReminderDispatching.swift` (modify) | `RemindMeMenuTarget` gains `rootCommentServerId` + comment `apId`; comment-target support |
| `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (modify) | "Remind Me…" in the comment context menu |
| `Spud/Scenes/Inbox/ReminderStatusText.swift` (modify) | subtree ("thread") status wording |
| `docs/features/reminders.md` (modify) | Phase-3 |

---

### Task 1: `v36` comment `childCount` + importer + sync read

**Files:** `AppDatabase+Migrations.swift`, `Records/Comment.swift`, `Importers/CommentImporter.swift`, a `*Queries.swift`; Test: `SpudDataKitTests/AppDatabase/CommentChildCountTests.swift`

**Interfaces — Produces:** `CommentRecord.childCount: Int64?` (server descendant count); `AppDatabase.commentChildCountSync(forKeychainId:serverCommentId:) -> Int?`.

- Migration `v36_commentChildCount` (next after `v35_reminder`): `ALTER TABLE comment ADD COLUMN childCount INTEGER` (nullable; older rows null until re-fetched). NEVER edit v35.
- `CommentImporter`: set `record.childCount = <the CommentView's server child_count>` on upsert (the neutral `CommentView`/`Comment` carries the descendant count — find the exact accessor, e.g. `view.counts.childCount` / `comment.childCount`; it's the same value Phase-1 stored on the load-more placeholder — reuse that source).
- `commentChildCountSync`: one-shot read of `comment.childCount` for `(account-of-keychainId's site, serverCommentId)`, mirroring `postNumberOfCommentsSync`.

- [ ] **Write tests:** importer round-trip via a `getComments` stub (or a direct `upsertComments` with a known child_count) → `commentChildCountSync` returns it; a comment fetched before the migration (null) reads nil. Use `AppDatabase.inMemory()`.
- [ ] **Implement.** Verify `make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: persist comment child_count (v36)`).

---

### Task 2: Subtree-capable reminder create/remove + poll

**Files:** `ReminderService.swift`, `ReminderNotificationScheduling.swift`; Test: `SpudDataKitTests/Reminders/ReminderSubtreeTests.swift`

**Interfaces — Consumes:** Task-1 `commentChildCountSync`. **Produces (generalize the Phase-1/2 methods — keep the whole-post default so existing callers compile unchanged):**
```swift
func setTimeReminder(postServerId:apId:fireAt:titleSnapshot:communityName:instanceHost:thumbnailUrl:, rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel) async throws
func removeTimeReminder(postServerId:, rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel) async throws
func setActivityReminder(postServerId:apId:baselineCount:titleSnapshot:communityName:instanceHost:thumbnailUrl:, rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel) async throws
func removeActivityReminder(postServerId:, rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel) async throws
// poll fetcher gains the subtree key:
func pollDueActivityReminders(asOf: Date, commentCountFetcher: @Sendable (_ postServerId: Int64, _ rootCommentServerId: Int64) async -> Int?) async
```
- The stable requestId helper now incorporates `rootCommentServerId` (`reminder-<acct>-<post>-<rootCommentServerId>-<kind>`) — so a whole-post and a subtree reminder on the same post schedule/cancel independently. Persist `rootCommentServerId` on the row (already a column). The upsert/remove `removeReminder(... rootCommentServerId:)` already keys on it (Phase 1).
- `pollDueActivityReminders`: for each due row call `commentCountFetcher(postServerId, rootCommentServerId)` (was `(postServerId)`); the rest of the fire/re-arm/bump logic is unchanged (count-delta).
- **`ReminderNotificationFactory`:** add `subtreeActivityContent(...)` (or a `isSubtree` flag on `activityReminderContent`) → body "N new replies" (vs whole-post "N new comments"); routingURL = `objectAtURL(apId)` where `apId` is the COMMENT's ap_id (so the tap scrolls to the comment). Time-reminder content for a subtree likewise uses the comment apId.

- [ ] **Write tests** (`ReminderSubtreeTests`, fake scheduler + `inMemory()`): `setActivityReminder(rootCommentServerId: 42, baselineCount: 3)` persists a row with `rootCommentServerId=42`; a whole-post AND a subtree activity reminder on the same post coexist (2 rows, distinct requestIds); `pollDueActivityReminders` with a fetcher keyed on `(post, 42)` returning a higher child_count fires the SUBTREE reminder + re-arms it and leaves the whole-post one alone; `removeTimeReminder(rootCommentServerId: 42)` removes only the subtree time reminder. Subtree notification body reads "N new replies".
- [ ] **Implement.** Verify `make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: subtree-scoped reminders + poll`).

---

### Task 3: Scheduler fetcher branches whole-post vs subtree

**Files:** `SchedulerService.swift`, and a `LemmyService` subtree-refresh seam if needed
**Test:** extend `SchedulerActivityPollTests` if cheap; else build + Task-2 coverage.

**Consumes:** Task-1 `commentChildCountSync`, Task-2 poll fetcher signature, `LemmyService.fetchComments(...)`.

- Update `pollActivityRemindersSweep`'s `commentCountFetcher` (`SchedulerService.swift:~355-361`) to the new `(postServerId, rootCommentServerId)` signature:
  ```swift
  let fetcher: @Sendable (Int64, Int64) async -> Int? = { postServerId, rootCommentServerId in
      if rootCommentServerId == ReminderRecord.wholePostSentinel {
          try? await lemmy.fetchPostInfo(serverPostId: Lemmy.PostID(postServerId))
          return appDatabase.postNumberOfCommentsSync(forKeychainId: keychainId, serverPostId: postServerId)
      } else {
          // Refresh the subtree so the root comment's child_count is current, then read it.
          try? await lemmy.fetchComments(<scope to the post or parentID = rootCommentServerId; verify the fetchComments overload>)
          return appDatabase.commentChildCountSync(forKeychainId: keychainId, serverCommentId: rootCommentServerId)
      }
  }
  ```
  Determine the right `fetchComments` overload to refresh a subtree (a `parentID`/`postID` scope — see `LemmyService.fetchComments` overloads; `getComments` mirrors the tree incl. the root's child_count into the `comment` table via `CommentImporter`, so after it `commentChildCountSync` is current). If a post-scoped `fetchComments` is simplest and already persists every comment's child_count (Task 1), prefer it over a parent-scoped call. Keep it best-effort (`try?`), per-account isolated, sequential — unchanged from Phase 2.

- [ ] **Write test (if cheap):** extend the scheduler integration test with a due SUBTREE activity reminder + a stub whose `getComments` returns a higher child_count → `tick()` fires it. Else note the skip (Task 2 covers the poll; this is wiring).
- [ ] **Implement.** Verify `make project && make build && make test-only ONLY=SpudDataKitTests`. **Commit** (`feat: poll subtree reminders in the scheduler`).

---

### Task 4: Comment context-menu entry + routing + Inbox status + docs

**Files:** `Spud/Reminders/PostReminderDispatching.swift`, `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, `Spud/Scenes/Inbox/ReminderStatusText.swift`, `docs/features/reminders.md`, `docs/features/README.md`
**Test:** `SpudTests` (menu-target / status)

**Consumes:** Task-2 subtree-capable `ReminderService` methods, `activeReminderKindsSync(accountId:postServerId:rootCommentServerId:)` (Phase 1, already keyed on `rootCommentServerId`), the comment row's `serverCommentId` + `originalCommentUrl` (its ap_id) + `childCount` (Task 1, for the activity baseline).

- **`RemindMeMenuTarget`** (`PostReminderDispatching.swift:17`): add `rootCommentServerId: Int64` (default `wholePostSentinel`) and make `apId` the comment's ap_id for a subtree target. Its callers currently build a whole-post target (`rootCommentServerId: wholePostSentinel` at :150); the checkmark/set/remove paths already pass a `rootCommentServerId` down — thread the target's value through instead of the hardcoded sentinel. For the activity baseline, use the comment's `childCount` (the subtree target's `numberOfComments` field carries the comment's child_count) with the `postNumberOfCommentsSync`/`commentChildCountSync` fallback.
- **Comment context menu** (`PostDetailViewController.swift` — the comment-row `contextMenuConfigurationForRowAt` / the comment `UIMenu` builder around the vote/save/reply/share actions): add the shared `makeRemindMeMenu(for:)` submenu, building a `RemindMeMenuTarget` from the comment row: `postServerId` = the post's, `rootCommentServerId` = `row.serverCommentId`, `apId` = `row.originalCommentUrl` (guard non-nil/non-empty — skip the submenu if the comment has no ap_id or no serverCommentId), title/community/instanceHost = the post's, `numberOfComments` = `row.childCount ?? 0` (subtree baseline). Reuse the exact seam the whole-post menu uses to reach the account scope + post fields.
- **Tap routing** is already correct via `objectAtURL(commentApId)` (Comments → `.objectAtURL` → scroll-to-comment) — verify a subtree reminder built this way opens the post scrolled to the comment on iPhone push + iPad split.
- **Inbox status** (`ReminderStatusText`): for a reminder whose `rootCommentServerId != 0`, note the thread scope — e.g. activity scheduled → "Watching a thread for new replies", fired → "New replies · tap to catch up"; time → keep the countdown but it's on a thread. Keep whole-post wording unchanged (branch on `rootCommentServerId != wholePostSentinel`). Update the VoiceOver label.
- **Docs:** `reminders.md` Phase-3 — following a comment thread (time + new-replies); the child_count/all-descendants semantics note; scroll-to-comment on tap. README table/by-area map.

- [ ] **Write tests:** if a pure helper decides subtree-vs-whole-post copy, test both; `RemindMeMenuTarget` default `rootCommentServerId == wholePostSentinel` (existing whole-post callers unchanged).
- [ ] **Implement.** Verify `make project && make build && make test-only ONLY=SpudTests && make test-only ONLY=SpudDataKitTests`. If the Inbox reminder cell renders a new subtree status, re-record `RemindersSegmentSnapshotTests` (fresh worktree: materialize annex pointers first per `SpudSnapshotTests/CLAUDE.md`). **Commit** (`feat: remind me on a comment thread`) + (`docs: reminders phase 3`).

---

## Notes for the executor

- Build the test targets after Task 1/2/3 (migration + service + scheduler). SourceKit "No such module" squiggles are unreliable — trust `make build`.
- Fresh worktree: snapshot refs are unmaterialized annex pointers — materialize before any snapshot run.
- Whole-post behavior (Phases 1-2) must stay byte-identical — the generalized methods keep `rootCommentServerId = wholePostSentinel` as the default, and the poll's whole-post branch is unchanged.
- Background poll (`BGAppRefreshTask`) is Phase 4, OUT of scope.
