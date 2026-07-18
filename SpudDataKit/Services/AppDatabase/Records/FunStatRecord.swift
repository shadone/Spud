//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// One accumulated "fun stats" counter bucket: the total `value` recorded for
/// `key` during local calendar `day` (yyyy-MM-dd) and local `hour` (0-23).
///
/// Rows are device-wide (no account column) and never pruned; they are
/// written exclusively through ``AppDatabase/incrementFunStats(_:)`` which
/// accumulates via upsert on the (day, hour, key) primary key.
public struct FunStatRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var day: String
    public var hour: Int
    public var key: String
    public var value: Double

    public static let databaseTableName = "funStat"

    public init(day: String, hour: Int, key: String, value: Double) {
        self.day = day
        self.hour = hour
        self.key = key
        self.value = value
    }
}
