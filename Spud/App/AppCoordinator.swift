//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import SpudDataKit
import WidgetKit

class AppCoordinator {
    static var shared: AppCoordinator {
        AppDelegate.shared.coordinator
    }

    let dependencies = DependencyContainer()

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

    func start() {
        dependencies.start()
    }
}
