//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// KeychainId + siteId pairs for non-ephemeral signed-out accounts whose
    /// home site has not had its site info imported yet and has not exceeded the
    /// give-up threshold. Sites still inside their back-off window
    /// (`siteInfoNextAttemptAt > now`) are excluded.
    ///
    /// Drives SchedulerService's first-fetch path: `site.name` is nil exactly
    /// when `SiteImporter.apply` has never run for the row.
    func signedOutAccountsAwaitingSiteInfo(now: Date) async throws -> [(keychainId: String, siteId: Int64)] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                    SELECT account.accountKeychainId AS keychainId, site.id AS siteId
                    FROM account
                    JOIN site ON site.id = account.siteId
                    WHERE account.isSignedOutAccountType = 1
                      AND account.isEphemeral = 0
                      AND site.name IS NULL
                      AND site.siteInfoConsecutivePermanentFailures < \(AppDatabase.siteInfoGiveUpThreshold)
                      AND (site.siteInfoNextAttemptAt IS NULL OR site.siteInfoNextAttemptAt <= ?)
                """, arguments: [now])
                .map { (keychainId: $0["keychainId"], siteId: $0["siteId"]) }
        }
    }

    /// ActorId + siteId pairs for sites that have no associated account yet,
    /// no imported site info, have not exceeded the give-up threshold, and are
    /// not inside a back-off window (`siteInfoNextAttemptAt > now`).
    func ownerlessSitesAwaitingInfo(now: Date) async throws -> [(actorId: InstanceActorId, siteId: Int64)] {
        let rows: [Row] = try await writer.read { db in
            try Row.fetchAll(db, sql: """
                    SELECT instance.actorId AS actorId, site.id AS siteId
                    FROM site
                    JOIN instance ON instance.id = site.instanceId
                    WHERE site.name IS NULL
                      AND NOT EXISTS (SELECT 1 FROM account WHERE account.siteId = site.id)
                      AND site.siteInfoConsecutivePermanentFailures < \(AppDatabase.siteInfoGiveUpThreshold)
                      AND (site.siteInfoNextAttemptAt IS NULL OR site.siteInfoNextAttemptAt <= ?)
                """, arguments: [now])
        }
        return rows.compactMap { row in
            let raw: String = row["actorId"]
            guard let actorId = InstanceActorId(from: raw) else {
                logger.error("Skipping unparseable instance actor id: \(raw, privacy: .public)")
                return nil
            }
            return (actorId: actorId, siteId: row["siteId"])
        }
    }

    /// Keychain ids of signed-in accounts that have never had `MyUserInfo`
    /// imported. `localAccountId` is nil until `AccountImporter.apply(myUser:)`
    /// has run, which only happens with a non-nil `myUser` payload.
    func signedInAccountsAwaitingMyUserInfo() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT accountKeychainId
                    FROM account
                    WHERE isSignedOutAccountType = 0
                      AND localAccountId IS NULL
                """)
        }
    }

    /// Keychain ids of signed-in accounts that already have `MyUserInfo`
    /// imported (`localAccountId IS NOT NULL`) and were last updated before
    /// `cutoff`. Drives the daily-refresh tick.
    func signedInAccountsStale(updatedBefore cutoff: Date) async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT accountKeychainId
                    FROM account
                    WHERE isSignedOutAccountType = 0
                      AND localAccountId IS NOT NULL
                      AND updatedAt < ?
                """, arguments: [cutoff])
        }
    }

    /// Keychain ids of every signed-in account (`isSignedOutAccountType = 0`),
    /// regardless of `MyUserInfo` staleness. Unlike `signedInAccountsAwaitingMyUserInfo`
    /// / `signedInAccountsStale` (which filter down to the subset due for a
    /// site-info refresh), this returns the full signed-in account set - the
    /// activity-reminder poll sweep (`SchedulerService.pollActivityRemindersSweep`)
    /// has its own due-gating per follow (`dueActivityRemindersSync`'s
    /// `nextCheckAt <= asOf`), so it needs every account to check, not a
    /// staleness-filtered subset. The `isSignedOutAccountType = 0` filter mirrors
    /// the signed-in site-info sweep's account scope (and, as a side effect,
    /// already excludes service accounts - `accountForSignedOut(isServiceAccount:)`
    /// always creates them as `isSignedOutAccountType = 1`).
    func signedInAccountKeychainIds() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT accountKeychainId
                    FROM account
                    WHERE isSignedOutAccountType = 0
                """)
        }
    }

    /// Keychain ids of every non-service REAL account - BOTH signed-in
    /// (`isSignedOutAccountType = 0`) and signed-out (`= 1`). Drives the
    /// activity-reminder poll sweep (`SchedulerService.pollActivityRemindersSweep`):
    /// unlike the two site-info sweeps, an activity follow ("When there are new
    /// comments") can be set while browsing signed out - `LemmyService.fetchPostInfo`
    /// (`getPost`) is anonymous, and Phase-1 TIME reminders already work
    /// signed-out - so the poll must reach every real account, not just
    /// `signedInAccountKeychainIds()` (which the signed-in site-info sweep still
    /// uses, unchanged).
    ///
    /// Excludes only **service accounts** (`isServiceAccount = 1`) - the
    /// background rows `accountForSignedOut(isServiceAccount: true)` creates for
    /// ownerless-site site-info fetches (`fetchSiteInfoForSignedOutIfNeeded`).
    /// These back no user-facing browsing session, so they can never carry a
    /// `reminder` row; polling them would be pure waste. Ephemeral one-off
    /// browse accounts (`isEphemeral = 1`, from `bestAccountKeychainId`) are
    /// deliberately NOT excluded here - unlike the site-info sweep (which would
    /// otherwise fire an unconditional network probe for every such account),
    /// this poll is cheap and due-gated (`dueActivityRemindersSync`'s
    /// `nextCheckAt <= asOf`), and a reminder set during an ephemeral browsing
    /// session is still a real reminder that must be polled.
    func pollableAccountKeychainIds() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT accountKeychainId
                    FROM account
                    WHERE isServiceAccount = 0
                """)
        }
    }
}
