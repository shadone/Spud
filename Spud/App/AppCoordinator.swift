//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import SpudWidgetData
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

        feedUpdated
            .sink { [weak self] feed in
                self?.updateWidgetDataIfNeeded(feed)
            }
            .store(in: &disposables)
    }

    private func updateWidgetDataIfNeeded(_ feed: LemmyFeed) {
        guard
            let topPosts = feed.pages
                .sorted(by: { $0.index < $1.index })
                .first?
                .pageElements
                .sorted(by: { $0.index < $1.index })
                // The max number of posts widget of any size might need.
                .prefix(6)
                .map(\.post)
        else {
            return
        }

        let value = TopPosts(posts: topPosts
            .compactMap(\.postInfo)
            .map { postInfo in
                let postType: Post.PostType
                if let thumbnailUrl = postInfo.thumbnailUrl {
                    postType = .image(thumbnailUrl)
                } else {
                    postType = .text
                }

                let postUrl = URL.SpudInternalLink.post(
                    postId: postInfo.post.postId,
                    instance: postInfo.post.account.site.instance.actorId
                ).url

                return .init(
                    spudUrl: postUrl,
                    title: postInfo.title,
                    type: postType,
                    community: .init(name: postInfo.communityName, site: "XXX"),
                    score: postInfo.score,
                    numberOfComments: postInfo.numberOfComments
                )
            }
        )

        WidgetDataProvider.shared.write(value)

        // TODO: check if the data has changed before reloading timelines.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
