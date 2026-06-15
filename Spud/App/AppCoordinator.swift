//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudDataKit
import SpudUIKit
import UIKit

private let logger = Logger.app

@MainActor
class AppCoordinator {
    static var shared: AppCoordinator {
        AppDelegate.shared.coordinator
    }

    let dependencies: DependencyContainer

    // MARK: Functions

    init() {
        let arguments = ProcessInfo.processInfo.arguments
            .compactMap { AppLaunchArgument(rawValue: $0) }
        dependencies = DependencyContainer(arguments: arguments)

        configureAppeareance()
    }

    func start() {
        dependencies.start()
    }

    private func configureAppeareance() {
        // Route bars through the theme-aware background token so the True-Black
        // (OLED) theme turns them pure black while standard light/dark stay on
        // the system materials. These are dynamic colors that re-resolve on a
        // trait change, so the swap is live with no per-bar override code.
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        navigationBarAppearance.backgroundColor = Theme.background

        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.backgroundColor = Theme.background

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Plain table/collection content surfaces (feeds, detail) follow the
        // theme background; grouped surfaces (settings) follow the grouped
        // token so cells stay legible against the black grouped background.
        UITableView.appearance().backgroundColor = Theme.background
    }

    func open(_ url: URL, in window: MainWindow) {
        switch url.spud {
        case let .post(postId, instance):
            let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
            window.display(serverPostId: postId, accountKeychainId: accountKeychainId)

        case .person:
            // TODO: open PersonVC
            break

        case .community:
            // TODO: open CommunityVC
            break

        case .objectAtURL, .instance:
            // Wired in the federated-link routing task.
            logger.warning("Unhandled internal link in AppCoordinator: \(url.absoluteString, privacy: .public)")

        case .none:
            logger.error("Received open url request for url that we can't handle: \(url.absoluteString, privacy: .public)")
        }
    }
}
