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

    /// The live navigation surface (the active `MainWindow`), registered by the
    /// scene delegate. Weak so a disconnected scene doesn't keep it alive.
    weak var activeWindow: AppNavigating?

    /// A navigation requested while no window was ready (e.g. an App Intent on
    /// cold launch). Replayed by `drainPendingNavigation()` once a window
    /// registers. One slot: the latest request wins.
    private(set) var pendingNavigation: AppNavigation?

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

        case let .community(name, instance):
            let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
            window.display(communityName: name, instance: instance, accountKeychainId: accountKeychainId)

        case let .person(personId, instance):
            let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
            window.display(personId: personId, instance: instance, accountKeychainId: accountKeychainId)

        case let .objectAtURL(canonicalURL):
            resolveAndDisplay(canonicalURL, in: window)

        case .instance:
            // No instance-home screen yet; bare instance links are out of scope.
            logger.error("Instance links are not handled yet: \(url.absoluteString, privacy: .public)")

        case .none:
            logger.error("Received open url request for url that we can't handle: \(url.absoluteString, privacy: .public)")
        }
    }

    /// Resolves a canonical Lemmy URL via `resolve_object` under the default
    /// account, then routes to the matching screen by the resolved object type.
    private func resolveAndDisplay(_ canonicalURL: URL, in window: MainWindow) {
        Task { @MainActor in
            guard let keychainId = dependencies.accountService.currentDefaultAccountKeychainId() else {
                logger.error("No default account to resolve link: \(canonicalURL.absoluteString, privacy: .public)")
                Haptics.warning()
                return
            }
            let lemmyService = dependencies.accountService.lemmyService(forAccountKeychainId: keychainId)
            let resolved = try? await lemmyService.resolveObject(query: canonicalURL.absoluteString)
            switch resolved {
            case let .post(postId, _):
                window.display(serverPostId: postId, accountKeychainId: keychainId)

            case let .community(name, instance):
                window.display(communityName: name, instance: instance, accountKeychainId: keychainId)

            case let .person(personId, instance):
                window.display(personId: personId, instance: instance, accountKeychainId: keychainId)

            case let .comment(postId, _, _):
                // TODO(Slice D): scroll to the resolved comment. For now open the
                // parent post so the link still lands somewhere useful.
                window.display(serverPostId: postId, accountKeychainId: keychainId)

            case .unresolved, .none:
                logger.error("Could not resolve an object to display for: \(canonicalURL.absoluteString, privacy: .public)")
                Haptics.warning()
            }
        }
    }

    // MARK: - Intent navigation

    /// Registers (or clears) the live navigation surface and replays any pending
    /// navigation the moment a window becomes available.
    func setActiveWindow(_ window: AppNavigating?) {
        activeWindow = window
        drainPendingNavigation()
    }

    /// Routes a navigation target to the live window, or stores it for replay if
    /// no window is ready yet (cold launch from an App Intent).
    func navigate(_ target: AppNavigation) {
        guard let window = activeWindow else {
            pendingNavigation = target
            return
        }
        apply(target, to: window)
    }

    /// Replays the stored pending navigation, if any, once a window is ready.
    func drainPendingNavigation() {
        guard let target = pendingNavigation, let window = activeWindow else { return }
        pendingNavigation = nil
        apply(target, to: window)
    }

    private func apply(_ target: AppNavigation, to window: AppNavigating) {
        switch target {
        case let .feed(listing, sort):
            window.selectFeed(listing: listing, sort: sort)

        case let .search(query):
            window.selectSearch(query: query)

        case .newPost:
            window.presentNewPost()

        case .inbox:
            window.selectInbox()

        case let .community(name, instance):
            let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
            window.display(communityName: name, instance: instance, accountKeychainId: accountKeychainId)

        case let .savedFeed(sort):
            window.selectSavedFeed(sort: sort)
        }
    }
}
