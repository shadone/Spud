//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os.log

private let logger = Logger(.widgetDataProvider)

public class WidgetDataProvider {
    public static let shared = WidgetDataProvider()

    let sharedFileURL: URL = {
        let appGroupIdentifier = "group.info.ddenis.Spud.Widget"
        guard
            let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            preconditionFailure("Expected a valid app group container")
        }
        return url.appendingPathComponent("top-posts.json")
    }()

    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()

    // MARK: Functions

    public func write(_ topPosts: TopPosts) {
        let data: Data
        do {
            data = try jsonEncoder.encode(topPosts)
        } catch {
            logger.error("Failed to encode widget data: \(error, privacy: .public)")
            return
        }

        do {
            try data.write(to: sharedFileURL)
        } catch {
            logger.error("Failed to write widget data: \(error, privacy: .public)")
        }

        logger.debug("Updated widget data.")
    }

    public func read() -> TopPosts? {
        let data: Data
        do {
            data = try Data(contentsOf: sharedFileURL)
        } catch {
            logger.error("Failed to read widget data: \(error, privacy: .public)")
            return nil
        }

        do {
            return try jsonDecoder.decode(TopPosts.self, from: data)
        } catch {
            logger.error("Failed to decode widget data: \(error, privacy: .public)")
            return nil
        }
    }
}
