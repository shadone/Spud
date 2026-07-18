//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A pending increment for one fun-stat bucket, produced by `StatsService`'s
/// in-memory accumulator and applied atomically by
/// ``AppDatabase/incrementFunStats(_:)``.
public struct FunStatDelta: Sendable, Equatable {
    public let day: String
    public let hour: Int
    public let key: String
    public let value: Double

    public init(day: String, hour: Int, key: String, value: Double) {
        self.day = day
        self.hour = hour
        self.key = key
        self.value = value
    }
}

public extension AppDatabase {
    /// Accumulates the given deltas into `funStat` in a single transaction:
    /// inserts a new (day, hour, key) bucket or adds to the existing value.
    func incrementFunStats(_ deltas: [FunStatDelta]) async throws {
        guard !deltas.isEmpty else { return }
        try await writer.write { db in
            for delta in deltas {
                try db.execute(
                    sql: """
                        INSERT INTO funStat (day, hour, key, value) VALUES (?, ?, ?, ?)
                        ON CONFLICT(day, hour, key) DO UPDATE SET value = value + excluded.value
                        """,
                    arguments: [delta.day, delta.hour, delta.key, delta.value]
                )
            }
        }
    }

    /// Deletes every fun-stat row. Backs the user-facing "Reset Stats" action.
    func clearFunStats() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM funStat")
        }
    }
}
