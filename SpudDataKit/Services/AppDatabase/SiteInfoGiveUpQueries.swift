//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// Consecutive permanent (4xx) site-info failures after which the scheduler
    /// permanently stops sweeping a site. A user-initiated on-demand fetch can
    /// still succeed and reset the state (see AccountService).
    static let siteInfoGiveUpThreshold = 5

    /// Back-off applied after a transient (5xx / timeout / offline) site-info
    /// failure. Kept short because transient failures should retry soon.
    static let siteInfoTransientRetryInterval: TimeInterval = 5 * 60

    /// Record a permanent site-info failure: increment the consecutive-permanent
    /// counter and push the back-off deadline out. Returns the new count so the
    /// caller can emit `site.giveUp` when it first reaches the threshold.
    func recordSiteInfoPermanentFailure(siteId: Int64, now: Date) throws -> Int {
        try writer.write { db in
            guard var site = try SiteRecord.fetchOne(db, key: siteId) else { return 0 }
            site.siteInfoConsecutivePermanentFailures += 1
            let delay = SchedulerBackoff.backoffDelay(failureCount: site.siteInfoConsecutivePermanentFailures)
            site.siteInfoNextAttemptAt = now.addingTimeInterval(delay)
            site.updatedAt = now
            try site.update(db)
            return site.siteInfoConsecutivePermanentFailures
        }
    }

    /// Record a transient site-info failure: leave the permanent counter (so a
    /// flaky instance is never abandoned) and schedule a short retry.
    func recordSiteInfoTransientFailure(siteId: Int64, now: Date) throws {
        try writer.write { db in
            guard var site = try SiteRecord.fetchOne(db, key: siteId) else { return }
            site.siteInfoNextAttemptAt = now.addingTimeInterval(Self.siteInfoTransientRetryInterval)
            site.updatedAt = now
            try site.update(db)
        }
    }

    /// Clear all give-up state for a site (called on any successful site-info
    /// import, so a user visit self-heals an abandoned site).
    ///
    /// - Note: This is a test-only seam. The production reset is performed inline
    ///   inside `SiteImporter.apply` on a successful site-info import. Do not call
    ///   this from production code paths; use the importer's inline reset instead.
    func resetSiteInfoGiveUpSync(siteId: Int64, db: Database) throws {
        guard var site = try SiteRecord.fetchOne(db, key: siteId) else { return }
        guard site.siteInfoConsecutivePermanentFailures != 0 || site.siteInfoNextAttemptAt != nil else { return }
        site.siteInfoConsecutivePermanentFailures = 0
        site.siteInfoNextAttemptAt = nil
        try site.update(db)
    }
}
