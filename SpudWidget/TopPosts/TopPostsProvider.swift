//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit
import UIKit
import WidgetKit
import os.log

private let logger = Logger(.topPostsProvider)

class TopPostsProvider: IntentTimelineProvider {
    typealias Dependencies =
        HasDataStore &
        HasAccountService
    private let dependencies: Dependencies

    typealias Entry = TopPostsEntry

    // MARK: Functions

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func placeholder(in context: Context) -> TopPostsEntry {
        TopPostsEntry(
            date: Date(),
            configuration: ConfigurationIntent(),
            topPosts: .placeholder,
            images: [:]
        )
    }

    func getSnapshot(
        for configuration: ConfigurationIntent,
        in context: Context,
        completion: @escaping (TopPostsEntry) -> ()
    ) {
        logger.debug("Snapshot requested")

        let now = Date()
        let entry = TopPostsEntry(
            date: now,
            configuration: configuration,
            topPosts: .placeholder, // TODO:
            images: [:]
        )

        logger.debug("Snapshot delivered")
        completion(entry)
    }

    func getTimeline(
        for configuration: ConfigurationIntent,
        in context: Context,
        completion: @escaping (Timeline<Entry>) -> ()
    ) {
        logger.debug("Timeline requested")

        Task {
            let feed = await fetchFeed()
            let entry = await entry(from: feed, for: configuration)

            let now = Date()
            let inOneHour = now.addingTimeInterval(60 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(inOneHour))

            logger.debug("Timeline delivered")
            completion(timeline)
        }
    }

    @MainActor func entry(
        from feed: LemmyFeed,
        for configuration: ConfigurationIntent
    ) async -> TopPostsEntry {
        let postInfos = feed.pages
            .sorted(by: { $0.index < $1.index })
            .first?
            .pageElements
            .sorted(by: { $0.index < $1.index })
            .map(\.post)
            .compactMap(\.postInfo)
            // The max number of posts widget of any size might need.
            .prefix(6) ?? []

        let topPosts = TopPosts(
            posts: postInfos
                .map { postInfo -> Post in
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

                    let community: Community
                    if let communityInfo = postInfo.community.communityInfo {
                        community = Community(
                            name: communityInfo.name,
                            site: communityInfo.hostnameFromActorId
                        )
                    } else {
                        community = Community(name: "-", site: "")
                    }

                    return .init(
                        spudUrl: postUrl,
                        title: postInfo.title,
                        type: postType,
                        community: community,
                        score: postInfo.score,
                        numberOfComments: postInfo.numberOfComments
                    )
                }
        )

        let imageUrls = topPosts.posts
            .compactMap { $0.type.imageUrl }

        let imagesByUrl = await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in imageUrls {
                group.addTask {
                    await (url, self.fetchImage(url))
                }
            }
            return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }

        return TopPostsEntry(
            date: Date(),
            configuration: configuration,
            topPosts: topPosts,
            images: imagesByUrl
        )
    }

    @MainActor func fetchFeed() async -> LemmyFeed {
        let account = dependencies.accountService.defaultAccount()
        let lemmyService = dependencies.accountService
            .lemmyService(for: account)

        let feed = lemmyService
            .createFeed(.frontpage(listingType: .all, sortType: .hot))

        do {
            try await lemmyService
                .fetchFeed(feedId: feed.objectID, page: nil)
                .async()
        } catch {
            logger.error("Failed to fetch feed: \(error, privacy: .public)")
        }

        self.dependencies.dataStore
            .mainContext
            .refresh(feed, mergeChanges: true)

        return feed
    }

    @MainActor private func fetchImage(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        return UIImage(data: data)?
            // We have to scale down the images as large images cannot be serialized by WidgetKit:
            // "Widget archival failed due to image being too large [3] - (4000, 3000)."
            .scalePreservingAspectRatio(targetSize: .init(width: 40, height: 40))
    }
}
