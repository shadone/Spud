//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct OutboxNetworkPerformingProtocolTests {
    @Test
    func fakeRecordsAndThrows() async throws {
        let fake = FakeOutboxPerformer()
        await fake.setOutcome(.fail(LemmyServiceError.requiresAuthentication), for: .vote)
        await #expect(throws: (any Error).self) {
            try await fake.perform(.init(entityType: .post, entityServerId: 1, desiredState: .vote(.liked)))
        }
        #expect(await fake.performed.count == 1)
    }
}
