//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class ExplorerCommunityDTOTests: XCTestCase {
    /// The lemmyverse community payload carries the community's creation date as a
    /// top-level `published` in Unix epoch *milliseconds*. The DTO must surface it
    /// and `makeRecord` must convert ms -> seconds (not treat it as seconds).
    func test_decode_publishedEpochMillis_mapsToCreationDate() throws {
        let json = Data("""
            {
                "baseurl": "lemmy.world",
                "url": "https://lemmy.world/c/technology",
                "name": "technology",
                "title": "Technology",
                "nsfw": false,
                "score": 0.9,
                "isSuspicious": false,
                "published": 1691620436000,
                "counts": { "subscribers": 100, "users_active_week": 10 }
            }
            """.utf8)

        let dto = try JSONDecoder().decode(ExplorerCommunityDTO.self, from: json)
        XCTAssertEqual(dto.published, 1_691_620_436_000)

        let record = dto.makeRecord(updatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(
            record.publishedAt,
            Date(timeIntervalSince1970: 1_691_620_436),
            "epoch ms must be divided by 1000"
        )
    }

    /// A community with no `published` (older crawls) decodes with a nil date
    /// rather than failing or defaulting to the epoch.
    func test_decode_missingPublished_isNil() throws {
        let json = Data("""
            { "baseurl": "lemmy.world", "url": "https://lemmy.world/c/x", "name": "x" }
            """.utf8)

        let dto = try JSONDecoder().decode(ExplorerCommunityDTO.self, from: json)
        XCTAssertNil(dto.published)
        XCTAssertNil(dto.makeRecord(updatedAt: Date(timeIntervalSince1970: 0)).publishedAt)
    }
}
