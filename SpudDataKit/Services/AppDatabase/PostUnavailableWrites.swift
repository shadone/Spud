//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB

public extension AppDatabase {
    /// Marks a post as no longer available on the server (`couldnt_find_post`).
    /// Idempotent; a no-op if no matching row exists. Cleared by a later PostView
    /// import (see `PostImporter`).
    func markPostUnavailable(accountId: Int64, serverPostId: Int64) async throws {
        try await writer.write { db in
            try OptimisticWrites.setPostUnavailable(
                db,
                accountId: accountId,
                serverPostId: serverPostId,
                isUnavailable: true
            )
        }
    }

    /// Keychain-scoped variant for callers (e.g. `LemmyService`) that hold the
    /// account's keychain id rather than its row id. Resolves the account row id
    /// inside the same write; a no-op if the account or post row is absent.
    func markPostUnavailable(forKeychainId keychainId: String, serverPostId: Int64) async throws {
        try await writer.write { db in
            guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                return
            }
            try OptimisticWrites.setPostUnavailable(
                db,
                accountId: accountId,
                serverPostId: serverPostId,
                isUnavailable: true
            )
        }
    }
}
