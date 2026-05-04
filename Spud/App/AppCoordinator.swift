//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudDataKit
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
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()

        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
    }

    func open(_ url: URL, in window: MainWindow) {
        switch url.spud {
        case let .post(postId, instance):
            let mainContext = dependencies.dataStore.mainContext
            let site = dependencies.siteService.site(for: instance, in: mainContext)
            let account = dependencies.accountService.account(at: site, in: mainContext)

            window.display(serverPostId: postId, accountKeychainId: account.id)

        case .person:
            // TODO: open PersonVC
            break

        case .none:
            logger.error("Received open url request for url that we can't handle: \(url.absoluteString, privacy: .public)")
        }
    }
}
