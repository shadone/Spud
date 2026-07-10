//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Idempotently ensures rows exist for `actorId`'s instance and its
    /// sibling site, without requiring a `GetSiteResponse`. Called by
    /// SiteService and the login flow so SchedulerService's GRDB queries
    /// see "fetch pending" rows whose `name` / `infoUpdatedDate` are nil.
    @discardableResult
    func ensureSite(
        forInstance actorId: InstanceActorId
    ) async throws -> (instanceId: Int64, siteId: Int64) {
        try await writer.write { db in
            let now = Date()
            let normalizedActorId = actorId.actorId

            let instanceId: Int64
            if var existing = try InstanceRecord
                .filter(InstanceRecord.Columns.actorId == normalizedActorId)
                .fetchOne(db)
            {
                existing.updatedAt = now
                try existing.update(db)
                instanceId = existing.id!
            } else {
                var record = InstanceRecord(
                    actorId: normalizedActorId,
                    createdAt: now,
                    updatedAt: now
                )
                try record.insert(db)
                instanceId = record.id!
            }

            let siteId: Int64
            if let existing = try SiteRecord
                .filter(Column("instanceId") == instanceId)
                .fetchOne(db)
            {
                siteId = existing.id!
            } else {
                var record = SiteRecord(
                    instanceId: instanceId,
                    createdAt: now,
                    updatedAt: now
                )
                try record.insert(db)
                siteId = record.id!
            }

            return (instanceId, siteId)
        }
    }

    /// Upserts an instance row and its sibling site row from the version-neutral
    /// ``LemmyKit/SiteInfo`` returned by `getSiteNeutral()`. Returns the resolved
    /// (instanceId, siteId).
    @discardableResult
    func upsertSite(
        from siteInfo: LemmyKit.SiteInfo
    ) async throws -> (instanceId: Int64, siteId: Int64) {
        let actorIdValue = siteInfo.site.apId
        guard let actorId = InstanceActorId(from: actorIdValue) else {
            logger.error("Invalid actor id: \(actorIdValue, privacy: .public)")
            throw SiteImporterError.invalidActorId(actorIdValue)
        }

        return try await writer.write { db in
            let now = Date()
            let normalizedActorId = actorId.actorId

            let instanceId: Int64 = try {
                if var existing = try InstanceRecord
                    .filter(InstanceRecord.Columns.actorId == normalizedActorId)
                    .fetchOne(db)
                {
                    existing.updatedAt = now
                    try existing.update(db)
                    return existing.id!
                } else {
                    var record = InstanceRecord(
                        actorId: normalizedActorId,
                        createdAt: now,
                        updatedAt: now
                    )
                    try record.insert(db)
                    return record.id!
                }
            }()

            let resolvedSiteId: Int64
            if var existing = try SiteRecord
                .filter(Column("instanceId") == instanceId)
                .fetchOne(db)
            {
                Self.apply(siteInfo: siteInfo, to: &existing, now: now)
                try existing.update(db)
                resolvedSiteId = existing.id!
            } else {
                var record = SiteRecord(instanceId: instanceId, updatedAt: now)
                Self.apply(siteInfo: siteInfo, to: &record, now: now)
                try record.insert(db)
                resolvedSiteId = record.id!
            }

            try Self.applyAdmins(siteInfo.admins, siteId: resolvedSiteId, db: db)

            return (instanceId, resolvedSiteId)
        }
    }

    /// Replaces the site's admin rows with `admins`, preserving API order via
    /// `ordinal`. `ON DELETE CASCADE` on the FK is not relied on here; we delete
    /// the prior set explicitly so a shrinking admin list converges.
    ///
    /// The neutral ``LemmyKit/SiteInfo`` carries admins as bare ``LemmyKit/Person``
    /// values (v4 flattened the admin's identity off the composed `PersonView`).
    private static func applyAdmins(
        _ admins: [Lemmy.Person],
        siteId: Int64,
        db: Database
    ) throws {
        try SiteAdminRecord
            .filter(Column("siteId") == siteId)
            .deleteAll(db)
        for (ordinal, person) in admins.enumerated() {
            var record = SiteAdminRecord(
                siteId: siteId,
                ordinal: ordinal,
                personActorId: person.apId,
                personName: person.name,
                displayName: person.displayName,
                avatarUrl: person.avatarUrl
            )
            try record.insert(db)
        }
    }

    private static func apply(
        siteInfo: LemmyKit.SiteInfo,
        to record: inout SiteRecord,
        now: Date
    ) {
        let site = siteInfo.site
        record.name = site.name
        // v4 renamed the site's `description` to the shorter `summary`.
        record.descriptionText = site.summary
        record.sidebar = site.sidebar
        record.iconUrl = site.iconUrl
        record.bannerUrl = site.bannerUrl
        record.version = siteInfo.version

        // `legalInformation`, `defaultPostListingType`, `enableDownvotes`, and
        // `enableNsfw` are admin-only `LocalSite` configuration the neutral
        // `SiteInfo` deliberately omits (no consumer reads them from getSite
        // today) — left untouched here: preserved on an update, nil on a fresh
        // insert. See the Phase 6 report follow-ups.

        record.numberOfPosts = site.posts
        record.numberOfComments = site.comments
        record.numberOfCommunities = site.communities
        record.numberOfUsers = site.users
        record.numberOfUsersDay = site.usersActiveDay
        record.numberOfUsersWeek = site.usersActiveWeek
        record.numberOfUsersMonth = site.usersActiveMonth
        record.numberOfUsersHalfYear = site.usersActiveHalfYear

        record.infoCreatedDate = site.publishedAt
        record.infoUpdatedDate = site.updatedAt

        // A successful site-info import clears any scheduler give-up state, so a
        // previously-abandoned instance resumes background refresh and a user
        // visit that succeeds self-heals it.
        record.siteInfoConsecutivePermanentFailures = 0
        record.siteInfoNextAttemptAt = nil

        record.updatedAt = now
    }
}

public enum SiteImporterError: Error {
    case invalidActorId(String)
}
