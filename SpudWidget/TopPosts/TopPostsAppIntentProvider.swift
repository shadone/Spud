//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import WidgetKit
import os.log

private let logger = Logger(.topPostsProvider)

@available(iOSApplicationExtension 17.0, *)
class TopPostsAppIntentProvider: AppIntentTimelineProvider {
    typealias Dependencies =
        HasEntryService
    private let dependencies: Dependencies

    // MARK: Private

    typealias Intent = ViewTopPostsAppIntent

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

    func snapshot(
        for configuration: ViewTopPostsAppIntent,
        in context: Context
    ) async -> TopPostsEntry {
        if context.isPreview {
            logger.debug("Snapshot requested for preview")
        } else {
            logger.debug("Snapshot requested")
        }

        let entry = dependencies.entryService.topPostsSnapshot()

        logger.debug("Snapshot delivered")

        return entry
    }

    func timeline(
        for configuration: ViewTopPostsAppIntent,
        in context: Context
    ) async -> Timeline<TopPostsEntry> {
        logger.debug("Timeline requested")

        let listingType = configuration.feedType
            .map { ListingType(from: $0) } ?? .subscribed
        let sortType = configuration.sortType
            .map { SortType(from: $0) } ?? .hot

        let entry = await dependencies.entryService
            .topPosts(listingType: listingType, sortType: sortType)

        let now = Date()
        let inOneHour = now.addingTimeInterval(60 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(inOneHour))

        logger.debug("Timeline delivered")

        return timeline
    }
}
