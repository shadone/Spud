//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class AccountEntityQueryTests: XCTestCase {
    private let world = AccountAppEntity(id: "kc-1", nickname: "alice", instanceHost: "lemmy.world")
    private let beehaw = AccountAppEntity(id: "kc-2", nickname: "bob", instanceHost: "beehaw.org")

    private func query() -> AccountEntityQuery {
        let entities = [world, beehaw]
        return AccountEntityQuery(load: { entities })
    }

    func test_suggestedEntities_returnsAll() async throws {
        let result = try await query().suggestedEntities()
        XCTAssertEqual(result.map(\.id), ["kc-1", "kc-2"])
    }

    func test_entitiesForIds_roundTripsById() async throws {
        let result = try await query().entities(for: ["kc-2"])
        XCTAssertEqual(result.map(\.id), ["kc-2"])
    }
}
