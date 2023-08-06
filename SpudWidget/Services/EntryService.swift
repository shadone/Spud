//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit
import os.log

private let logger = Logger(.entryService)

protocol EntryServiceType: AnyObject {
    func startService()

    func topPosts(for configuration: TopPostsConfigurationIntent) async -> TopPostsEntry
}

protocol HasEntryService {
    var entryService: EntryServiceType { get }
}

class EntryService: EntryServiceType {
    let dataStore: DataStoreType
    let accountService: AccountServiceType

    init(
        dataStore: DataStoreType,
        accountService: AccountServiceType
    ) {
        self.dataStore = dataStore
        self.accountService = accountService
    }

    func startService() { }

    func topPosts(for configuration: TopPostsConfigurationIntent) async -> TopPostsEntry {
        let feed = await fetchFeed()
        let entry = await entry(from: feed, for: configuration)
        return entry
    }

    @MainActor private func entry(
        from feed: LemmyFeed,
        for configuration: TopPostsConfigurationIntent
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

    @MainActor private func fetchFeed() async -> LemmyFeed {
        let account = accountService.defaultAccount()
        let lemmyService = accountService
            .lemmyService(for: account)

        let feed = lemmyService
            .createFeed(.frontpage(listingType: .local, sortType: .new))

        do {
            try await lemmyService
                .fetchFeed(feedId: feed.objectID, page: nil)
                .async()
        } catch {
            logger.error("Failed to fetch feed: \(error, privacy: .public)")
        }

        dataStore
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
