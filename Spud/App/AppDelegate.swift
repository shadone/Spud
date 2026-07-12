//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import UIKit
import UserNotifications

#if DEBUG
import SBTUITestTunnelServer
#endif

private let logger = Logger.app

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    static var shared: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    let coordinator: AppCoordinator

    override init() {
        // Test-only: wipe the App Group AppDatabase BEFORE anything opens it.
        // `AppCoordinator()` below builds the DI graph, whose
        // `DependencyContainer.init` sets `appDatabase = .shared` — the FIRST
        // open of the on-disk store in the app process. That open happens during
        // this instance's initialization (the coordinator is a stored property),
        // which precedes `application(_:didFinishLaunchingWithOptions:)`, so the
        // wipe cannot live there and be early enough — it must run here, ahead of
        // the coordinator. The App Group database survives SBT's ResetFilesystem
        // and `simctl uninstall`, so this is the only reliable fresh-install seam
        // for UI tests. Reads no `self` state, so it is legal before the stored
        // property is assigned. Never reached in the shipping app.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(AppLaunchArgument.wipeAppDatabase.rawValue) {
            AppDatabase.wipePersistentStoreForUITests()
        }
        #endif
        coordinator = AppCoordinator()
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        coordinator.start()

        // Own notification-tap routing / foreground presentation before any
        // reminder is ever scheduled (Task 5) - a delegate set later than the
        // first delivered notification would silently miss it.
        UNUserNotificationCenter.current().delegate = self

        // Apply the local interaction-log retention policy in the background.
        // Best-effort: a failure just leaves old rows until the next launch.
        Task {
            try? await AppDatabase.shared.prunePostInteractions()
        }

        // Prune orphaned feed rows from prior sessions. Every feed is minted
        // with a fresh UUID feedKey on demand and no feedKey survives a launch,
        // so feeds older than a short margin are unreachable orphans.
        // Best-effort: a failure just leaves stale rows until the next launch.
        Task {
            try? await AppDatabase.shared.pruneStaleFeedRows()
        }

        #if DEBUG
        SBTUITestTunnelServer.takeOff()
        #endif
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

// MARK: - UNUserNotificationCenterDelegate (reminder tap routing)

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Fires when the user taps a delivered reminder notification (or one of
    /// its actions). Routes it through the same deep-link funnel every other
    /// system entry point uses (`AppCoordinator.open`) - see
    /// `routeNotificationTap(routingURLString:)`.
    ///
    /// `nonisolated`: `UNUserNotificationCenterDelegate` requirements are not
    /// actor-isolated, but `AppDelegate` inherits `@MainActor` isolation from
    /// `UIResponder` - a non-`nonisolated` witness fails to satisfy the
    /// protocol under Swift 6 strict concurrency (the delegate call site
    /// can't guarantee it's already on the main actor). The main-actor work
    /// itself hops over via `Task { @MainActor in ... }`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Pull the one Sendable value we need out of `userInfo`
        // ([AnyHashable: Any], not Sendable) here, synchronously, so the
        // Task closure below only captures a plain String? across the actor
        // hop.
        let routingURLString = response.notification.request.content
            .userInfo[ReminderNotificationContent.userInfoRoutingURLKey] as? String
        Task { @MainActor in
            AppDelegate.routeNotificationTap(routingURLString: routingURLString)
        }
        completionHandler()
    }

    /// Without this override, a notification delivered while the app is in
    /// the foreground is suppressed entirely by default - a reminder must
    /// still surface (banner + Notification Center entry + sound) even while
    /// the user is actively using the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Decodes a tapped notification's `spudRoutingURL` userInfo payload
    /// (written by `UNReminderNotificationScheduler.schedule`) and opens it
    /// via `AppCoordinator.open`, mirroring how `SceneDelegate.scene(_:
    /// openURLContexts:)` and `scene(_:continue:)` reach the same funnel for
    /// deep links and Handoff/Spotlight.
    ///
    /// A cold launch races this against scene connection: `didReceive` can
    /// fire before `SceneDelegate.scene(_:willConnectTo:)` has finished
    /// standing up the `MainWindow`. Rather than drop the tap, poll briefly
    /// for the window to appear (bounded, so an app that never connects a
    /// scene at all can't leak a runaway task).
    @MainActor
    private static func routeNotificationTap(routingURLString: String?) {
        guard
            let routingURLString,
            let url = URL(string: routingURLString)
        else {
            logger.error("Notification tap carried no usable routing URL")
            return
        }

        if let window = activeMainWindow {
            AppCoordinator.shared.open(url, in: window)
            return
        }

        Task { @MainActor in
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(100))
                if let window = activeMainWindow {
                    AppCoordinator.shared.open(url, in: window)
                    return
                }
            }
            logger.error("Notification tap: no active window appeared to route \(url.absoluteString, privacy: .public)")
        }
    }

    /// The active `MainWindow`, if any. Mirrors the fallback
    /// `PostListViewController+OfflineDownload.offlineDownloadWindow` uses to
    /// anchor UI with no view of its own on screen: prefer a foreground-active
    /// scene's key window, falling back to its first window.
    @MainActor
    private static var activeMainWindow: MainWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .compactMap { $0 as? MainWindow }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
