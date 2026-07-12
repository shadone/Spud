//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import UIKit

private let logger = Logger.app

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: MainWindow?

    /// Covers the window with a privacy screen when NSFW content is on screen and
    /// the app backgrounds (the app-switcher snapshot) or the screen is captured.
    private var privacyScreen: PrivacyScreen?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Use this method to optionally configure and attach the UIWindow `window` to the
        // provided UIWindowScene `scene`.
        // This delegate does not imply the connecting scene or session are new (see
        // `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = MainWindow(
            windowScene: windowScene,
            dependencies: AppCoordinator.shared.dependencies
        )
        self.window = window
        privacyScreen = PrivacyScreen(window: window)

        // Register the window as the live navigation surface and replay any
        // navigation an App Intent requested before the UI was ready.
        AppCoordinator.shared.setActiveWindow(window)

        if let url = connectionOptions.urlContexts.first?.url {
            AppCoordinator.shared.open(url, in: window)
        }

        if let activity = connectionOptions.userActivities.first {
            routeContinuedActivity(activity, in: window)
        }

        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        AppCoordinator.shared.setActiveWindow(nil)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Re-register as the active navigation surface and drain any pending
        // App Intent navigation queued while the app was inactive.
        if let window {
            AppCoordinator.shared.setActiveWindow(window)
        }
        privacyScreen?.sceneDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        // Cover NSFW content before iOS snapshots the app for the app switcher.
        privacyScreen?.sceneWillResignActive()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Refresh the inbox unread count so the badge is current when the user
        // returns to the app.
        window?.refreshUnreadCount()

        let dependencies = AppCoordinator.shared.dependencies

        // Durable foreground event: visible in About → Logs as a relaunch-history marker.
        Task {
            await dependencies.diagnosticLog.record(
                category: .lifecycle,
                level: .info,
                event: "lifecycle.foreground",
                message: "App entered foreground",
                instance: nil,
                metadata: nil
            )
        }

        // Keep the Spotlight community index current with any subscription
        // changes made while we were away.
        CommunitySpotlightIndexer.reindex(appDatabase: dependencies.appDatabase, diagnostics: dependencies.diagnosticLog)
        ContentSpotlightIndexer.reindex(appDatabase: dependencies.appDatabase, diagnostics: dependencies.diagnosticLog)

        // Retry any pending outbox ops for the active account. There's no backoff
        // timer, so foreground (alongside reconnect and enqueue) is a retry
        // trigger — this covers being foregrounded with pending ops but no
        // connectivity change since.
        let accountService = dependencies.accountService
        if let keychainId = accountService.currentDefaultAccountKeychainId() {
            let scope = accountService.scope(forAccountKeychainId: keychainId)
            Task { await scope.drainPendingOutbox() }

            // Catch any time reminders that fired while backgrounded/not running
            // to receive the OS notification callback - mirrors the Spotlight
            // reindex calls above. Best-effort: a failed reconcile just leaves
            // the badge stale until the next launch/foreground.
            Task { try? await scope.reminderService.reconcileOverdue(asOf: Date()) }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific
        // state information to restore the scene back to its current state.
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for urlContext in URLContexts {
            logger.debug("""
                Received open URL request: \(urlContext.url, privacy: .public) \
                [\
                sourceApplication=\(urlContext.options.sourceApplication ?? "nil", privacy: .public), \
                eventAttribution=\(String(describing: urlContext.options.eventAttribution), privacy: .public)\
                ]
                """)
        }

        guard let url = URLContexts.first?.url else { return }

        guard let window else {
            logger.assertionFailure("Huh, no window?")
            return
        }

        AppCoordinator.shared.open(url, in: window)
    }

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
}
