//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "info.ddenis.Spud", category: "FunStatObservations")

public extension AppDatabase {
    /// Live Fun Stats summary; re-emits whenever any `funStat` row changes.
    func observeFunStatsSummary(
        calendar: Calendar,
        now: @escaping @Sendable () -> Date
    ) -> AsyncStream<FunStatsSummary> {
        let observation = ValueObservation
            .tracking { db -> FunStatsSummary in
                try Self.funStatsSummary(db: db, calendar: calendar, today: now())
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            // ValueObservation.start defaults to .async(onQueue: .main), which
            // is @MainActor-isolated and illegal from this non-isolated
            // AsyncStream init closure. All *Observations.swift helpers in
            // this project use .async(onQueue: .global(qos: .userInitiated)).
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("observeFunStatsSummary failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
