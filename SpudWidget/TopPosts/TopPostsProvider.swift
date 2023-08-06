//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
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
            let entry = await dependencies.entryService.topPosts(for: configuration)

            let now = Date()
            let inOneHour = now.addingTimeInterval(60 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(inOneHour))

            logger.debug("Timeline delivered")
            completion(timeline)
        }
    }
}
