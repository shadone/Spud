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
    /// Replaces the `postCrossPost` junction rows for the opened post
    /// `postServerId` with `crossPostServerIds`, in server order. A re-fetch
    /// always REPLACES the set (existing rows for this post are deleted first,
    /// then one row per surviving id is inserted) — it never appends, and an
    /// empty `crossPostServerIds` simply clears the junction (a post that lost
    /// its cross-posts on a later fetch shows none).
    ///
    /// No-ops (leaves any existing junction rows untouched) if `postServerId`
    /// isn't mirrored under `keychainId` — the call site
    /// (`LemmyService.fetchPostInfo`) always mirrors the opened post first, so
    /// this only defends against being called out of order. A `crossPostServerIds`
    /// entry that isn't (yet) mirrored is silently skipped — the call site mirrors
    /// every cross-post `PostView` immediately before calling this, so a skip only
    /// defends against a partially-failed harvest.
    func replaceCrossPosts(
        forPostServerId postServerId: Int64,
        crossPostServerIds: [Int64],
        forKeychainId keychainId: String
    ) async throws {
        try await writer.write { db in
            guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                return
            }
            guard let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == postServerId)
                .fetchOne(db)?
                .id
            else {
                return
            }

            try PostCrossPostRecord
                .filter(Column("postId") == postRowId)
                .deleteAll(db)

            for (index, crossPostServerId) in crossPostServerIds.enumerated() {
                guard let crossPostRowId = try PostRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("postId") == crossPostServerId)
                    .fetchOne(db)?
                    .id
                else {
                    logger.debug("""
                        Skipping cross-post junction row - cross-post \
                        \(crossPostServerId, privacy: .public) not yet in AppDatabase
                        """)
                    continue
                }
                var junction = PostCrossPostRecord(
                    postId: postRowId,
                    crossPostId: crossPostRowId,
                    position: Int64(index)
                )
                try junction.insert(db)
            }
        }
    }
}
