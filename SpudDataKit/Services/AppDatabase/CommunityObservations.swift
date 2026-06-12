//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Resolves the server-side community id of a cached community owned by
    /// `accountId`, matched by its federation actor id. Synchronous so the
    /// community screen can decide at bring-up whether it already has the
    /// community cached (and can skip the network fetch). Returns nil if the
    /// community hasn't been imported for this account yet.
    func communityServerIdSync(
        forAccountId accountId: Int64,
        actorId: String
    ) -> Int64? {
        do {
            return try writer.read { db in
                try Int64.fetchOne(db, sql: """
                        SELECT community.communityId
                        FROM community
                        WHERE community.accountId = ?
                          AND community.actorId = ?
                        LIMIT 1
                    """, arguments: [accountId, actorId])
            }
        } catch {
            logger.error("Failed to resolve community server id: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
