//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

/// Actor-based helpers used instead of Atomic (which is a @propertyWrapper and
/// not usable as Atomic(false)/.value from a @Sendable closure in Swift 6).
private actor Counter {
    private(set) var n = 0
    func bump() {
        n += 1
    }
}

private actor Flag {
    private(set) var value = false
    func set() {
        value = true
    }
}

final class LinkEmbedServiceTests: XCTestCase {
    private func youtubeOEmbedJSON(title: String) -> Data {
        #"{"title":"\#(title)","thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"}"#.data(using: .utf8)!
    }

    func test_youtube_returnsTitleAndDerivedThumbnail() async throws {
        let json = youtubeOEmbedJSON(title: "Never Gonna Give You Up")
        let service = LinkEmbedService { _ in json }
        let result = try await service.embed(for: XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        let embed = try XCTUnwrap(result)
        XCTAssertEqual(embed.kind, .video)
        XCTAssertEqual(embed.title, "Never Gonna Give You Up")
        XCTAssertEqual(embed.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }

    func test_nonVideoLink_returnsNilWithoutFetching() async throws {
        let fetched = Flag()
        let service = LinkEmbedService { _ in
            await fetched.set()
            return nil
        }
        let embed = try await service.embed(for: XCTUnwrap(URL(string: "https://example.com/article")))
        XCTAssertNil(embed)
        let wasFetched = await fetched.value
        XCTAssertFalse(wasFetched, "must not fetch for a non-video link")
    }

    func test_oEmbedFailure_keepsDerivedThumbnail() async throws {
        let service = LinkEmbedService { _ in nil } // network/JSON failure
        let result = try await service.embed(for: XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        let embed = try XCTUnwrap(result)
        XCTAssertNil(embed.title)
        XCTAssertEqual(embed.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }

    func test_cache_secondCallDoesNotRefetch() async throws {
        let count = Counter()
        let json = youtubeOEmbedJSON(title: "t")
        let service = LinkEmbedService { _ in
            await count.bump()
            return json
        }
        _ = try await service.embed(for: XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        _ = try await service.embed(for: XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        let n = await count.n
        XCTAssertEqual(n, 1)
    }
}
