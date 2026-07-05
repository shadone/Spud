//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

#if DEBUG
import SBTUITestTunnelServer
#endif

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
