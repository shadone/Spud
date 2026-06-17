//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class CommunityEntityQueryTests: XCTestCase {
    private let tech = CommunityAppEntity(
        id: "technology@lemmy.world",
        name: "technology",
        instanceActorId: "https://lemmy.world",
        iconURLString: nil
    )
    private let ask = CommunityAppEntity(
        id: "askscience@beehaw.org",
        name: "askscience",
        instanceActorId: "https://beehaw.org",
        iconURLString: nil
    )

    private func query() -> CommunityEntityQuery {
        let entities = [tech, ask]
        return CommunityEntityQuery(load: { entities })
    }

    func test_suggestedEntities_returnsAll() async throws {
        let result = try await query().suggestedEntities()
        XCTAssertEqual(result.map(\.id), ["technology@lemmy.world", "askscience@beehaw.org"])
    }

    func test_entitiesMatching_filtersByNameCaseInsensitively() async throws {
        let result = try await query().entities(matching: "TECH")
        XCTAssertEqual(result.map(\.name), ["technology"])
    }

    func test_entitiesForIds_roundTripsById() async throws {
        let result = try await query().entities(for: ["askscience@beehaw.org"])
        XCTAssertEqual(result.map(\.id), ["askscience@beehaw.org"])
    }
}
