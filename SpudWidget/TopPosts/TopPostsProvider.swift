//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import UIKit
import WidgetKit

private let logger = Logger.topPostsProvider

class TopPostsProvider: IntentTimelineProvider {
    typealias Dependencies =
        HasEntryService
    private let dependencies: Dependencies

    typealias Entry = TopPostsEntry

    // MARK: Functions

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func placeholder(in context: Context) -> TopPostsEntry {
        TopPostsEntry(
            date: Date(),
            topPosts: .placeholder,
            images: [:]
        )
    }

    func getSnapshot(
        for configuration: ViewTopPostsIntent,
        in context: Context,
        completion: @escaping (TopPostsEntry) -> Void
    ) {
        if context.isPreview {
            logger.debug("Snapshot requested for preview")
        } else {
            logger.debug("Snapshot requested")
        }

        let entry = dependencies.entryService.topPostsSnapshot()

        logger.debug("Snapshot delivered")
        completion(entry)
    }

    func getTimeline(
        for configuration: ViewTopPostsIntent,
        in context: Context,
        completion: @escaping (Timeline<Entry>) -> Void
    ) {
        logger.debug("Timeline requested")

        let listingType = Components.Schemas.ListingType(from: configuration.feedType) ?? .Subscribed
        let sortType = Components.Schemas.SortType(from: configuration.sortType) ?? .Hot

        Task {
            let entry = await dependencies.entryService
                .topPosts(listingType: listingType, sortType: sortType)

            let now = Date()
            let inOneHour = now.addingTimeInterval(60 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(inOneHour))

            logger.debug("Timeline delivered")
            completion(timeline)
        }
    }
}
