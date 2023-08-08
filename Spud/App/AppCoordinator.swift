//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import SpudDataKit
import os.log

private let logger = Logger(.app)

class AppCoordinator {
    static var shared: AppCoordinator {
        AppDelegate.shared.coordinator
    }

    let dependencies: DependencyContainer

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    private var feedUpdated: AnyPublisher<LemmyFeed, Never> = NotificationCenter.default
        .publisher(for: .NSManagedObjectContextObjectsDidChange)
        .compactMap { notification -> LemmyFeed? in
            guard
                let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? NSSet
            else {
                return nil
            }
            let feeds = updatedObjects.compactMap { $0 as? LemmyFeed }
            assert(feeds.count <= 1)
            return feeds.first
        }
        .eraseToAnyPublisher()

    // MARK: Functions

    init() {
        let arguments = ProcessInfo.processInfo.arguments
            .compactMap { AppLaunchArgument(rawValue: $0) }
        dependencies = DependencyContainer(arguments: arguments)
    }

    func start() {
        dependencies.start()
    }

    func open(_ url: URL, in window: MainWindow) {
        switch url.spud {
        case let .post(postId, instance):
            // FIXME: for now assume the post's instance is the same as the default account.
            _ = instance
            let account = AppCoordinator.shared.dependencies.accountService.defaultAccount()
            let postDetailVC = PostDetailOrEmptyViewController(
                account: account,
                dependencies: AppCoordinator.shared.dependencies
            )
            postDetailVC.startLoadingPost(postId: postId)

            window.display(post: postDetailVC)

        case .person:
            // TODO: open PersonVC
            break

        case .none:
            logger.error("Received open url request for url that we can't handle: \(url.absoluteString, privacy: .public)")
        }
    }
}
