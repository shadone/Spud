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
    /// Stream of all real (non-service) accounts ordered by sign-in state then
    /// keychain id. The first element is emitted as soon as the observation
    /// starts; further elements arrive whenever the underlying rows change.
    func observeAccounts() -> AsyncStream<[AccountRecord]> {
        let observation = ValueObservation
            .tracking { db in
                try AccountRecord
                    .filter(Column("isServiceAccount") == false)
                    .order(
                        Column("isSignedOutAccountType").asc,
                        Column("accountKeychainId").asc
                    )
                    .fetchAll(db)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of accounts for a specific site, ordered by keychain id.
    func observeAccounts(forSiteId siteId: Int64) -> AsyncStream<[AccountRecord]> {
        let observation = ValueObservation
            .tracking { db in
                try AccountRecord
                    .filter(Column("siteId") == siteId)
                    .filter(Column("isServiceAccount") == false)
                    .order(Column("accountKeychainId").asc)
                    .fetchAll(db)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of a single site row identified by primary key. Yields nil if
    /// the row no longer exists.
    func observeSite(id siteId: Int64) -> AsyncStream<SiteRecord?> {
        let observation = ValueObservation
            .tracking { db in
                try SiteRecord.fetchOne(db, key: siteId)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    private func makeStream<Value: Sendable>(
        observation: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<Value>>>
    ) -> AsyncStream<Value> where Value: Equatable {
        AsyncStream { continuation in
            let cancellable = observation.start(in: writer) { error in
                logger.error("ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
