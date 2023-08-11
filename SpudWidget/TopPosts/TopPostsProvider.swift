//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import UIKit
import WidgetKit
import os.log

private let logger = Logger(.topPostsProvider)

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
        completion: @escaping (TopPostsEntry) -> ()
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
        completion: @escaping (Timeline<Entry>) -> ()
    ) {
        logger.debug("Timeline requested")

        let listingType = ListingType(from: configuration.feedType) ?? .subscribed
        let sortType = SortType(from: configuration.sortType) ?? .hot

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
