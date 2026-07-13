//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import BackgroundTasks
import Foundation
import SpudDataKit

/// `BGAppRefreshTask` predates Swift concurrency and isn't `Sendable`, but
/// Apple's own documented contract for it is exactly the shape used below:
/// `setTaskCompleted`/`expirationHandler` are meant to be touched from
/// whichever context (the async poll's completion, or the system's own
/// expiration callback) finishes first, on whatever thread that happens to
/// be. `CompletionGuard` (below) is what actually serializes the "exactly
/// once" invariant; this conformance only tells the compiler the reference
/// itself is safe to share across those two completion-path closures.
extension BGAppRefreshTask: @unchecked Sendable { }

/// Registers, schedules, and handles the Phase-4 `BGAppRefreshTask` that lets
/// the activity-reminder poll (`SchedulerService.runReminderPoll`) fire even
/// when the app isn't foregrounded (spec §5.3/§9.4). This is purely a
/// background *trigger* for the existing poll - the fire rule / count-delta /
/// re-arm logic all live in Phases 2-3's `pollActivityRemindersSweep` and are
/// never reimplemented here.
///
/// Honesty: iOS decides IF/WHEN this actually runs - it's opportunistic, and
/// can be delayed hours or skipped entirely if Background App Refresh is off
/// or the app is rarely used. The foreground 5-minute tick
/// (`SchedulerService.startService`) remains the reliable-while-open path;
/// this is only a best-effort supplement for when the app is closed.
enum ReminderBackgroundRefresh {
    /// Must exactly match the single entry in `BGTaskSchedulerPermittedIdentifiers`
    /// (`Spud/Resources/Info.plist`) - `BGTaskScheduler.register` refuses (returns
    /// `false`) for an identifier not declared there.
    static let taskIdentifier = "info.ddenis.Spud.reminderPoll"

    /// Floor on when a freshly-submitted request may next fire, relative to
    /// `now`. Not a promise: iOS may run it later, or skip a given window
    /// entirely.
    static let refreshInterval: TimeInterval = 2 * 60 * 60

    /// Registers the launch handler with the OS. MUST be called synchronously
    /// from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`,
    /// before it returns - registering late, or more than once for the same
    /// identifier, is an iOS-level error (the system kills the app on a
    /// duplicate registration).
    ///
    /// The launch handler itself runs off-main on a system-managed queue
    /// (`using: nil` hands it a private serial queue); `schedulerService` is a
    /// `@MainActor` class, so `await schedulerService.runReminderPoll()`
    /// inside `handle` correctly hops back onto the main actor for that call.
    static func register(schedulerService: SchedulerServiceType, diagnostics: DiagnosticLogging) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, schedulerService: schedulerService, diagnostics: diagnostics)
        }
    }

    /// Reschedules the next request UNCONDITIONALLY - regardless of whether
    /// this run succeeds or expires - then runs one poll sweep for a
    /// launched task and completes. `task.setTaskCompleted(success:)` is
    /// called EXACTLY ONCE across the success and expiration paths -
    /// `completionGuard` (an actor, not a plain `Bool`) is what enforces
    /// that, because the poll's completion and the OS's expiration callback
    /// race on independent threads (the OS can expire the task in the same
    /// instant the poll finishes).
    private static func handle(
        _ task: BGAppRefreshTask,
        schedulerService: SchedulerServiceType,
        diagnostics: DiagnosticLogging
    ) {
        let completionGuard = CompletionGuard()

        // A BGAppRefreshTask never repeats on its own, and Apple's canonical
        // pattern is to submit the next request up front, before running the
        // work - not only from a success continuation. Scheduling ONLY on
        // success (the previous shape) meant an EXPIRED run submitted
        // nothing, so background polling silently stopped until the next
        // foreground->background transition re-seeded it. Submission is
        // idempotent (replaces any still-pending request), so scheduling here
        // is safe even before this run's own poll has started. `schedule()`
        // is `@MainActor` (it reaches `AppCoordinator.shared`); this `Task`
        // isn't - it hops over explicitly.
        Task {
            await schedule()
        }

        let pollTask = Task {
            await schedulerService.runReminderPoll()

            guard await completionGuard.markCompletedIfFirst() else { return }
            task.setTaskCompleted(success: true)
            await diagnostics.record(
                category: .reminder,
                level: .debug,
                event: "bg.ran",
                message: "Background reminder poll ran to completion",
                instance: nil,
                metadata: nil
            )
        }

        task.expirationHandler = {
            pollTask.cancel()
            Task {
                guard await completionGuard.markCompletedIfFirst() else { return }
                // iOS grants only a short window after `expirationHandler`
                // fires before force-terminating the process (and
                // penalizing future scheduling) - complete FIRST, then do
                // the best-effort diagnostic write (a GRDB App-Group SQLite
                // write that can block under WAL contention), so a slow
                // write can never cost us the graceful
                // `setTaskCompleted(success:)`.
                task.setTaskCompleted(success: false)
                await diagnostics.record(
                    category: .reminder,
                    level: .notice,
                    event: "bg.expired",
                    message: "Background reminder poll expired before completing",
                    instance: nil,
                    metadata: nil
                )
            }
        }
    }

    /// Submits the next `BGAppRefreshTaskRequest`. Idempotent - submitting
    /// again for the same identifier replaces any still-pending request
    /// rather than queuing a second one. Call once at launch and every time
    /// the app backgrounds (`SceneDelegate.sceneDidEnterBackground`), so
    /// there's always a fresh request pending.
    ///
    /// `@MainActor`: reaches `AppCoordinator.shared.dependencies.diagnosticLog`
    /// (mirroring how `SceneDelegate` already reaches the dependency graph),
    /// which is only safe to touch on the main actor. Both app-side callers
    /// (`AppDelegate.didFinishLaunching`, `SceneDelegate.sceneDidEnterBackground`)
    /// are already on the main actor; the background handler calls it
    /// unconditionally at entry from its own `Task`, so this also runs
    /// regardless of how the launched task ends.
    @MainActor
    static func schedule() {
        let request = makeRequest(now: Date())
        let diagnostics = AppCoordinator.shared.dependencies.diagnosticLog
        do {
            try BGTaskScheduler.shared.submit(request)
            Task {
                await diagnostics.record(
                    category: .reminder,
                    level: .debug,
                    event: "bg.scheduled",
                    message: "Scheduled next background reminder poll",
                    instance: nil,
                    metadata: nil
                )
            }
        } catch {
            // Best-effort: BGTaskScheduler can refuse submission (e.g. no
            // simulator support, or the per-identifier pending-request cap) -
            // the foreground poll remains the reliable-while-open path either
            // way, so a failed submit here is never fatal. Still log it -
            // otherwise a stuck pending-request cap silently stops background
            // polling with no visibility in About -> Logs.
            Task {
                await diagnostics.record(
                    category: .reminder,
                    level: .notice,
                    event: "bg.scheduleFailed",
                    message: "Failed to submit next background reminder poll request",
                    instance: nil,
                    metadata: ["error": String(describing: error)]
                )
            }
        }
    }

    /// Builds the next refresh request. Pure (no OS interaction), so it's
    /// unit-testable without a device: `identifier` matches `taskIdentifier`,
    /// and `earliestBeginDate` is `now + refreshInterval`.
    static func makeRequest(now: Date) -> BGAppRefreshTaskRequest {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = now.addingTimeInterval(refreshInterval)
        return request
    }

    /// Guards `task.setTaskCompleted` against being called twice from the two
    /// racing completion paths (the poll's success continuation and
    /// `expirationHandler`). An actor rather than `Atomic<Bool>`
    /// (`SpudUtilKit`), because `Atomic`'s property-wrapper storage can't be
    /// shared-and-mutated from inside two independent closures under Swift 6
    /// (see `LinkEmbedServiceTests`'s `Flag` actor for the same pattern).
    /// Internal (not `private`) so `ReminderBackgroundRefreshTests` can drive
    /// it directly via `@testable import`.
    actor CompletionGuard {
        private var completed = false

        /// Returns `true` (and flips the flag) only the first time it's
        /// called; every subsequent call returns `false`.
        func markCompletedIfFirst() -> Bool {
            guard !completed else { return false }
            completed = true
            return true
        }
    }
}
