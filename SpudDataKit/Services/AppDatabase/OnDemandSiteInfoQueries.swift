//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// True when an account is ephemeral (a browse account, excluded from the
    /// recurring scheduler sweep) AND its site info has not been imported yet
    /// (`site.name IS NULL`). Drives the one best-effort on-demand `getSite`
    /// fired when the user opens a browse instance. Returns false once site info
    /// lands, so it fires at most once per open of a still-unfetched instance.
    func shouldFetchSiteInfoOnDemandSync(forAccountKeychainId keychainId: String) -> Bool {
        (try? writer.read { db in
            try Bool.fetchOne(db, sql: """
                    SELECT 1 FROM account
                    JOIN site ON site.id = account.siteId
                    WHERE account.accountKeychainId = ?
                      AND account.isEphemeral = 1
                      AND site.name IS NULL
                """, arguments: [keychainId]) ?? false
        }) ?? false
    }
}
