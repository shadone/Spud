//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct CommunityEntityQueryTests {
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

    @Test
    func suggestedEntities_returnsAll() async throws {
        let result = try await query().suggestedEntities()
        #expect(result.map(\.id) == ["technology@lemmy.world", "askscience@beehaw.org"])
    }

    @Test
    func entitiesMatching_filtersByNameCaseInsensitively() async throws {
        let result = try await query().entities(matching: "TECH")
        #expect(result.map(\.name) == ["technology"])
    }

    @Test
    func entitiesForIds_roundTripsById() async throws {
        let result = try await query().entities(for: ["askscience@beehaw.org"])
        #expect(result.map(\.id) == ["askscience@beehaw.org"])
    }
}
