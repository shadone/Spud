# Post Reminders — Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Poll activity ("new comments/replies") follows in the **background** via a `BGAppRefreshTask`, so a follow can fire a notification even when the app is closed — plus cancel a removed account's scheduled reminders (no orphans). This completes the reminders feature.

**Architecture:** A `BGAppRefreshTask` (identifier `info.ddenis.Spud.reminderPoll`) is registered at launch and scheduled when the app backgrounds. When iOS runs it, its handler runs the SAME reminder poll the foreground `SchedulerService` runs (extracted to a public entry point), posts notifications, reschedules the next task, and completes within the OS budget (with an expiration handler). No new migration; no paid entitlement (just `UIBackgroundModes` + `BGTaskSchedulerPermittedIdentifiers` in Info.plist). Timing is OS-controlled and opportunistic — documented as best-effort.

**Tech stack:** Swift 6 strict concurrency, `BackgroundTasks`, UIKit, GRDB, UserNotifications, Swift Testing. Spec: `docs/superpowers/specs/2026-07-12-post-reminders-design.md` (§5.3 background, §6 constraints, §9.4). Phases 1-3 merged (base).

## Global Constraints

- Phase 4 = the `BGAppRefreshTask` background poll + account-teardown reminder cleanup. The poll LOGIC (fire rule, count-delta, re-arm, subtree branch) is Phases 2-3 and must be REUSED, not reimplemented.
- **No new migration.** `BGAppRefreshTask` needs NO paid entitlement — only `UIBackgroundModes` (`fetch`) + `BGTaskSchedulerPermittedIdentifiers` (the task id) in `Spud/Resources/Info.plist`. Do NOT add a push entitlement.
- **Registration timing:** `BGTaskScheduler.shared.register(forTaskWithIdentifier:)` MUST be called synchronously in `application(_:didFinishLaunchingWithOptions:)` before it returns (iOS requirement) — for EVERY identifier declared in Info.plist.
- **Budget + completion:** the handler MUST set `task.expirationHandler` (cancel the in-flight poll) AND always call `task.setTaskCompleted(success:)` exactly once, AND reschedule the next `BGAppRefreshTaskRequest` (a task doesn't auto-repeat). Keep the work bounded (the poll only touches due follows; iOS gives ~30s).
- **Honesty:** iOS decides IF/WHEN a `BGAppRefreshTask` runs (opportunistic, can be delayed hours or skipped if the app is rarely used / Background App Refresh is off). Document it as best-effort; the foreground poll (Phases 2-3) remains the reliable-while-open path.
- Native-iOS bar; Swift 6 strict concurrency (`SchedulerService` is `@MainActor`; the BGTask handler hops to it); Swift Testing; no emojis. GRDB date binding. After DI changes, build the test targets.
- Docs: `docs/features/reminders.md` (Phase-4) + README table/by-area map + reconcile `diagnostics-logging.md` (new `.reminder` bg events already exist from Phase 2).
- Worktree `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/post-reminders-p4` (branch `feat/post-reminders-p4`). Stage explicit paths. Commit trailers:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY`. `make project` after Info.plist/project.yml/source changes.

## File structure

| File | Responsibility |
|---|---|
| `Spud/Resources/Info.plist` (modify) | `UIBackgroundModes`=[`fetch`] + `BGTaskSchedulerPermittedIdentifiers`=[`info.ddenis.Spud.reminderPoll`] |
| `SpudDataKit/Services/Scheduler/SchedulerService.swift` (modify) | expose a public `runReminderPoll() async` wrapping the existing private sweep |
| `Spud/Reminders/ReminderBackgroundRefresh.swift` (create) | register / schedule / handle the `BGAppRefreshTask` (identifier, request, handler, reschedule, diagnostics) |
| `Spud/App/AppDelegate.swift` (modify) | register the task in `didFinishLaunching`; schedule on background |
| `Spud/App/SceneDelegate.swift` (modify, if used) | schedule the next refresh in `sceneDidEnterBackground` |
| `SpudDataKit/Services/Reminders/ReminderService.swift` (modify) | `removeAllReminders()` (delete this account's rows + cancel their OS requests) |
| `SpudDataKit/Services/Account/AccountService.swift` (modify) | call `removeAllReminders()` in `logout`/`removeAccount` before dropping the cached service |
| `SpudDataKit/Services/AppDatabase/ReminderWrites.swift` (modify) | `removeAllReminders(accountId:) -> [String]` (delete rows, return notificationRequestIds) |
| `docs/features/reminders.md`, `README.md` (modify) | Phase-4 |

---

### Task 1: `BGAppRefreshTask` background reminder poll

**Files:** `Info.plist`, `SchedulerService.swift`, `Spud/Reminders/ReminderBackgroundRefresh.swift` (create), `AppDelegate.swift`, `SceneDelegate.swift`; Test: `SpudTests/Reminders/ReminderBackgroundRefreshTests.swift`

**Interfaces — Produces:**
```swift
// SchedulerService (public entry the BG handler + the foreground tick share):
func runReminderPoll() async   // wraps the existing private pollActivityRemindersSweep()
// ReminderBackgroundRefresh (app):
enum ReminderBackgroundRefresh {
    static let taskIdentifier = "info.ddenis.Spud.reminderPoll"
    static let refreshInterval: TimeInterval = 2 * 60 * 60   // earliest 2h out; iOS decides actual timing
    /// Registers the handler. Call in didFinishLaunching (before it returns).
    static func register(schedulerService: SchedulerServiceType, diagnostics: DiagnosticLogging)
    /// Submits the next BGAppRefreshTaskRequest (idempotent; call on background).
    static func schedule()
    /// Builds the next request (pure, testable): earliestBeginDate = now + refreshInterval.
    static func makeRequest(now: Date) -> BGAppRefreshTaskRequest
}
```
- **`SchedulerService.runReminderPoll()`:** make the existing `pollActivityRemindersSweep()` reachable — add a public `runReminderPoll()` on `SchedulerServiceType` + `SchedulerService` that just `await`s the sweep. The foreground `tick()` can call it too (or keep calling the private one — either is fine; the point is a public entry for the BG handler). No behavior change to the sweep.
- **`register`:** `BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in ... }`. In the handler (a `BGAppRefreshTask`): set `task.expirationHandler = { <cancel the poll Task> }`; start a `Task { await schedulerService.runReminderPoll(); ReminderBackgroundRefresh.schedule() /* reschedule */; task.setTaskCompleted(success: true) }`; on expiration cancel + `setTaskCompleted(success: false)`. Emit `.reminder` diagnostics (`bg.ran`/`bg.expired`). Ensure `setTaskCompleted` is called EXACTLY once on every path.
- **`schedule`:** `try? BGTaskScheduler.shared.submit(makeRequest(now: Date()))`; log `bg.scheduled`. Idempotent (submitting replaces the pending request for that id).
- **`AppDelegate.didFinishLaunching`** (`:47-56`, right where `UNUserNotificationCenter.current().delegate` is set): `ReminderBackgroundRefresh.register(schedulerService:diagnostics:)` (reach them via the dependency graph the AppDelegate already uses — grep how AppDelegate/DependencyContainer expose `schedulerService`). Also call `schedule()` once at launch.
- **`SceneDelegate.sceneDidEnterBackground`** (`:120`): call `ReminderBackgroundRefresh.schedule()` so a fresh request is pending each time the app backgrounds.
- **`Info.plist`** (`Spud/Resources/Info.plist`): add `UIBackgroundModes` array with `fetch`, and `BGTaskSchedulerPermittedIdentifiers` array with `info.ddenis.Spud.reminderPoll`. (`make project` regenerates the xcodeproj; verify the keys survive.)

- [ ] **Write tests** (`ReminderBackgroundRefreshTests`, SpudTests): `taskIdentifier == "info.ddenis.Spud.reminderPoll"`; `makeRequest(now:)` sets `identifier == taskIdentifier` and `earliestBeginDate == now + refreshInterval`. (The register/handle/OS integration is on-device — the pure request-building + identifier are the unit-testable surface. If `SchedulerService.runReminderPoll` is cheaply testable — it just forwards to the sweep — a test that it invokes the poll can piggyback on the Phase-2 scheduler harness; else skip and note.)
- [ ] **Implement.** Verify `make project && make build && make test-only ONLY=SpudTests`. Confirm the Info.plist keys are present in the built app (`plutil -p` the built Info.plist, or grep the generated project). **Commit** (`feat: background reminder poll via BGAppRefreshTask`).

---

### Task 2: Account-teardown reminder cleanup + docs

**Files:** `ReminderWrites.swift`, `ReminderService.swift`, `AccountService.swift`, `docs/features/reminders.md`, `README.md`; Test: `SpudDataKitTests/Reminders/ReminderTeardownTests.swift`

**Interfaces — Produces:**
```swift
// AppDatabase:
func removeAllReminders(accountId: Int64) async throws -> [String]   // delete all of the account's reminder rows; return their non-nil notificationRequestIds
// ReminderService (actor):
func removeAllReminders() async   // appDatabase.removeAllReminders(accountId:) then scheduler.cancel(each returned requestId)
```
- **The gap (owed fast-follow):** `reminder.accountId` has no cascade, so logging out / removing an account leaves its reminder rows AND its scheduled OS notifications orphaned (a time reminder for a removed account would still fire later). Fix by cleanup, not a migration edit (v35 is shipped) — and cleanup ALSO cancels the OS notifications, which a DB cascade wouldn't.
- **`AccountService.logout` / `removeAccount`** (they already do `reminderServices[keychainId] = nil` — added in Phase 1): BEFORE dropping the cached service, `await reminderService(forAccountKeychainId: keychainId).removeAllReminders()` (best-effort; these methods are `@MainActor` — wrap the await appropriately, e.g. a `Task { }` if they can't be async, matching how they already do async cleanup; if they're fully synchronous, do the cleanup fire-and-forget in a detached Task and note it). Ensure the cleanup runs against the CORRECT account before the row is deleted by `deleteAccountSync`.

- [ ] **Write tests** (`ReminderTeardownTests`, fake scheduler + `inMemory()`): seed an account with 2 time + 1 activity reminder (time ones have notificationRequestIds); `removeAllReminders()` deletes all 3 rows AND calls `scheduler.cancel` for each stored requestId; a second account's reminders are untouched.
- [ ] **Implement** the cleanup + wire into logout/removeAccount. **Docs:** `reminders.md` Phase-4 — background delivery + the honest iOS-opportunistic-timing caveat (Background App Refresh must be on; timing not guaranteed; foreground poll is the reliable-while-open path); account removal cancels its reminders. README table/by-area map (mark reminders "shipped"/complete for the planned scope).
- [ ] **Verify** `make project && make build && make test-only ONLY=SpudDataKitTests && make test-only ONLY=SpudTests`. **Commit** (`feat: cancel an account's reminders on teardown`) + (`docs: reminders phase 4`).

---

## Notes for the executor

- Build the test targets after Task 1/2 (SchedulerServiceType + AccountService changes). SourceKit "No such module" squiggles are unreliable — trust `make build`.
- `BGTaskScheduler` only runs tasks on a real device / a Debug build with the scheme's "Launch due to a background fetch event" or the LLDB `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"info.ddenis.Spud.reminderPoll"]` trick — so the background PATH is on-device/manual to verify; unit tests cover only the pure request-building + the cleanup. Note this in the on-device-verify owed list.
- Do NOT reimplement the poll — `runReminderPoll` forwards to the Phase-2/3 sweep unchanged.
- This is a fresh worktree: snapshot refs are unmaterialized annex pointers (no snapshot work expected in Phase 4, but if any, materialize first).
