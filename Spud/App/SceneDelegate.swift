//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import os.log
import SpudDataKit
import UIKit

private let logger = Logger(.app)

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: MainWindow?

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

        if let url = connectionOptions.urlContexts.first?.url {
            AppCoordinator.shared.open(url, in: window)
        }

        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific
        // state information to restore the scene back to its current state.

        // Save changes in the application's managed object context when the application
        // transitions to the background.
        AppCoordinator.shared.dependencies.dataStore.saveIfNeeded()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach { urlContext in
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
}
