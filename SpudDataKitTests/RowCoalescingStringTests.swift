//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import Testing
@testable import SpudDataKit

/// Locks the fix for the GRDB `row["a"] ?? row["b"]` nil-coalescing footgun.
///
/// Regression for the reported bug where comments (and the post header) whose
/// creator had no `display_name` rendered a blank author: chaining two GRDB
/// column subscripts through `??` made a NULL *left* column collapse the whole
/// expression to `nil` instead of falling through to the right column, so the
/// username was lost. `Row.coalescingString(_:)` reads each column on its own
/// and must coalesce correctly.
struct RowCoalescingStringTests {
    /// Round-trips the values through a real statement-backed row (NULL handled
    /// the same way the observation queries see it).
    private func coalesce(displayName: String?, name: String?) throws -> String? {
        let queue = try DatabaseQueue()
        return try queue.write { db in
            try db.execute(sql: "CREATE TABLE t (displayName TEXT, name TEXT)")
            try db.execute(
                sql: "INSERT INTO t (displayName, name) VALUES (?, ?)",
                arguments: [displayName, name]
            )
            let row = try Row.fetchOne(db, sql: "SELECT displayName, name FROM t")!
            return row.coalescingString("displayName", "name")
        }
    }

    @Test
    func nullDisplayNameFallsBackToName() throws {
        // The reported bug: a null display_name must show the username, not blank.
        #expect(try coalesce(displayName: nil, name: "manmachine") == "manmachine")
    }

    @Test
    func displayNameWinsWhenPresent() throws {
        #expect(try coalesce(displayName: "HobbitFoot", name: "hobbit") == "HobbitFoot")
    }

    @Test
    func nullNameStillReturnsDisplayName() throws {
        #expect(try coalesce(displayName: "Display", name: nil) == "Display")
    }

    @Test
    func bothNullReturnsNil() throws {
        #expect(try coalesce(displayName: nil, name: nil) == nil)
    }
}
