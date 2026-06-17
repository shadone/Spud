//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// The federation actor id (`ap_id`) for a person identified by its server
    /// id, for the first matching row. A one-shot synchronous read, safe off the
    /// main thread (used by the Person screen to vend an NSUserActivity). nil
    /// when unknown or the column is empty.
    func personActorIdSync(forServerPersonId serverPersonId: Int64) -> String? {
        (try? writer.read { db -> String? in
            try String.fetchOne(
                db,
                sql: "SELECT actorId FROM person WHERE personId = ? LIMIT 1",
                arguments: [serverPersonId]
            )
        }) ?? nil
    }
}
