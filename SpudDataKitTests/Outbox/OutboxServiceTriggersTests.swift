//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

@MainActor
struct OutboxServiceTriggersTests {
    @Test
    func reconnectDrainsBackedOffRows() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .vote)
        let monitor = StaticReachabilityMonitor(isOnline: false)
        let service = OutboxService(
            accountId: accountId,
            appDatabase: appDatabase,
            performer: performer,
            reachability: monitor,
            now: { 1000 },
            diagnostics: DiagnosticLogSpy(),
            instance: "lemmy.test"
        )
        await service.start()

        // Offline enqueue: transient failure — row stays, backed-off with nextAttemptAt > 1000.
        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).count == 1)

        // Succeed and reconnect; drainAll should pick up the backed-off row.
        await performer.setOutcome(.success, for: .vote)
        monitor.setOnline(true)
        try await Task.sleep(nanoseconds: 50_000_000) // let the reachability task run
        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
    }
}
