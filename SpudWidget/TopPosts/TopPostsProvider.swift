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

class TopPostsProvider: IntentTimelineProvider {
    typealias Entry = TopPostsEntry

    let dependencies = DependencyContainer()

    // MARK: Functions

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
        let now = Date()
        let entry = TopPostsEntry(
            date: now,
            configuration: configuration,
            topPosts: .placeholder, // TODO:
            images: [:]
        )
        completion(entry)
    }

    func getTimeline(
        for configuration: ConfigurationIntent,
        in context: Context,
        completion: @escaping (Timeline<Entry>) -> ()
    ) {
        Task {
            let feed = await fetchFeed()

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

            let now = Date()

            let entry = TopPostsEntry(
                date: now,
                configuration: configuration,
                topPosts: topPosts,
                images: imagesByUrl
            )

            let inOneHour = now.addingTimeInterval(60 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(inOneHour))
            completion(timeline)
        }
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
            print("### Failed to fetch feed: \(error)")
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
