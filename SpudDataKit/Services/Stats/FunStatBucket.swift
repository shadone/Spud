//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The (local day, local hour) bucket a fun-stat increment lands in.
public struct FunStatBucket: Hashable, Sendable {
    public let day: String
    public let hour: Int

    public init(day: String, hour: Int) {
        self.day = day
        self.hour = hour
    }

    /// Formats `date` into a bucket using the given calendar's time zone.
    /// A traveler's time-zone changes can blur bucket boundaries; that is an
    /// accepted approximation for a fun feature (see the design spec).
    public static func make(date: Date, calendar: Calendar) -> FunStatBucket {
        // Built per call: a cached DateFormatter would not be concurrency-safe
        // in a non-MainActor type under strict concurrency.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return FunStatBucket(
            day: formatter.string(from: date),
            hour: calendar.component(.hour, from: date)
        )
    }
}
