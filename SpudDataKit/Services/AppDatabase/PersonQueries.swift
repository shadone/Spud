//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// The federation actor id (`ap_id`) for a person identified by its unique
    /// database row id (`person.id`). A one-shot synchronous read, safe off the
    /// main thread (used by the Person screen to vend an NSUserActivity). nil
    /// when unknown or the column is empty.
    ///
    /// Keying on the primary key (`person.id`) is unambiguous across federated
    /// sites — the same server-side `personId` can appear on multiple sites.
    func personActorIdSync(forPersonRowId rowId: Int64) -> String? {
        (try? writer.read { db -> String? in
            try String.fetchOne(
                db,
                sql: "SELECT actorId FROM person WHERE id = ? LIMIT 1",
                arguments: [rowId]
            )
        }) ?? nil
    }
}
