//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import UIKit

private let logger = Logger(.entryService)

protocol EntryServiceType: AnyObject {
    func startService()

    func topPostsSnapshot() -> TopPostsEntry

    func topPosts(
        listingType: Components.Schemas.ListingType,
        sortType: Components.Schemas.SortType
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

    @MainActor
    func topPosts(
        listingType: Components.Schemas.ListingType,
        sortType: Components.Schemas.SortType
    ) async -> TopPostsEntry {
        let feed = await fetchFeed(listingType: listingType, sortType: sortType)

        let topPosts = TopPosts(from: feed)
        let entry = await entry(from: topPosts)

        return entry
    }

    @MainActor
    private func entry(
        from topPosts: TopPosts
    ) async -> TopPostsEntry {
        let imageUrls = topPosts.posts
            .compactMap(\.type.imageUrl)

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

    @MainActor
    private func fetchFeed(
        listingType: Components.Schemas.ListingType,
        sortType: Components.Schemas.SortType
    ) async -> LemmyFeed {
        let account = accountService.defaultAccount()
        let lemmyService = accountService
            .lemmyService(for: account)

        let listingType: Components.Schemas.ListingType = {
            switch listingType {
            case .Subscribed:
                return account.isSignedOutAccountType ? .All : .Subscribed
            case .ModeratorView:
                return account.isSignedOutAccountType ? .All : .ModeratorView
            case .All, .Local:
                return listingType
            }
        }()

        let feed = lemmyService
            .createFeed(.frontpage(listingType: listingType, sortType: sortType))
        feed.identifierForDebugging = "widget"

        do {
            try await lemmyService
                .fetchFeed(feedId: feed.objectID, page: nil)
        } catch {
            logger.error("Failed to fetch feed: \(error, privacy: .public)")
        }

        dataStore
            .mainContext
            .refresh(feed, mergeChanges: true)

        return feed
    }

    @MainActor
    private func fetchImage(_ url: URL) async -> UIImage? {
        // TODO: look into fetching images using background request
        // https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension

        logger.debug("Fetching image \(url, privacy: .public)")

        var data: Data?
        data = await (try? URLSession.shared.data(from: url))?.0

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
