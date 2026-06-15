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

        case let .objectAtURL(canonicalURL):
            Task { @MainActor in
                guard let keychainId = dependencies.accountService.currentDefaultAccountKeychainId() else {
                    logger.error("No default account to resolve link: \(canonicalURL.absoluteString, privacy: .public)")
                    return
                }
                let lemmyService = dependencies.accountService.lemmyService(forAccountKeychainId: keychainId)
                guard
                    let resolved = try? await lemmyService.resolveObject(query: canonicalURL.absoluteString),
                    case let .post(postId, _) = resolved
                else {
                    logger.error("Could not resolve a post to display for: \(canonicalURL.absoluteString, privacy: .public)")
                    return
                }
                window.display(serverPostId: postId, accountKeychainId: keychainId)
            }

        case .person, .community, .instance:
            // These push onto a navigation stack, which AppCoordinator does not
            // own; body-text taps route through PostDetailViewController instead.
            logger.error("Internal link type not handled at window level: \(url.absoluteString, privacy: .public)")

        case .none:
            logger.error("Received open url request for url that we can't handle: \(url.absoluteString, privacy: .public)")
        }
    }
}
