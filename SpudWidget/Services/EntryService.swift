//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import LemmyKit
import UIKit
import os.log

private let logger = Logger(.entryService)

protocol EntryServiceType: AnyObject {
    func startService()

    func topPostsSnapshot() -> TopPostsEntry

    func topPosts(
        listingType: ListingType,
        sortType: SortType
    ) async -> TopPostsEntry
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

    func topPostsSnapshot() -> TopPostsEntry {
        let snapshot = TopPosts.snapshot

        let now = Date()
        let entry = TopPostsEntry(
            date: now,
            topPosts: snapshot,
            images: snapshot.resolveImagesFromAssets
        )

        return entry
    }

    @MainActor func topPosts(
        listingType: ListingType,
        sortType: SortType
    ) async -> TopPostsEntry {
        let feed = await fetchFeed(listingType: listingType, sortType: sortType)

        let topPosts = TopPosts(from: feed)
        let entry = await entry(from: topPosts)

        return entry
    }

    @MainActor private func entry(
        from topPosts: TopPosts
    ) async -> TopPostsEntry {
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

        logger.debug("Done, returning entry")

        return TopPostsEntry(
            date: Date(),
            topPosts: topPosts,
            images: imagesByUrl
        )
    }

    @MainActor private func fetchFeed(
        listingType: ListingType,
        sortType: SortType
    ) async -> LemmyFeed {
        let account = accountService.defaultAccount()
        let lemmyService = accountService
            .lemmyService(for: account)

        let listingType: ListingType = {
            switch listingType {
            case .subscribed:
                return account.isSignedOutAccountType ? .all : .subscribed
            case .all, .local:
                return listingType
            }
        }()

        let feed = lemmyService
            .createFeed(.frontpage(listingType: listingType, sortType: sortType))

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
        // TODO: look into fetching images using background request
        // https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension

        logger.debug("Fetching image \(url, privacy: .public)")

        var data: Data?
        data = (try? await URLSession.shared.data(from: url))?.0

        guard data != nil else {
            return nil
        }

        guard let image = UIImage(data: data!) else {
            return nil
        }

        let sizeInBytes = data!.count
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        logger.debug("Got image \(width, privacy: .public)x\(height, privacy: .public) \(sizeInBytes, privacy: .public) bytes")

        // release raw network response from memory
        data = nil

        if max(image.size.width, image.size.height) > 500 {
            logger.debug("Scaling down image")
            // We have to scale down the images as large images cannot be serialized by WidgetKit:
            // "Widget archival failed due to image being too large [3] - (4000, 3000)."
            return image
                .scalePreservingAspectRatio(targetSize: .init(width: 40, height: 40))
        }

        logger.debug("Returning image as is")
        return image
    }
}
