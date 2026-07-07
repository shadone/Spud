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

    /// Upserts an instance row and its sibling site row from a `GetSite` API
    /// response. Returns the resolved (instanceId, siteId).
    @discardableResult
    func upsertSite(
        from response: Lemmy.GetSiteResponse
    ) async throws -> (instanceId: Int64, siteId: Int64) {
        let actorIdValue = response.site_view.site.actor_id
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
                Self.apply(response: response, to: &existing, now: now)
                try existing.update(db)
                resolvedSiteId = existing.id!
            } else {
                var record = SiteRecord(instanceId: instanceId, updatedAt: now)
                Self.apply(response: response, to: &record, now: now)
                try record.insert(db)
                resolvedSiteId = record.id!
            }

            try Self.applyAdmins(response.admins, siteId: resolvedSiteId, db: db)

            return (instanceId, resolvedSiteId)
        }
    }

    /// Replaces the site's admin rows with `admins`, preserving API order via
    /// `ordinal`. `ON DELETE CASCADE` on the FK is not relied on here; we delete
    /// the prior set explicitly so a shrinking admin list converges.
    private static func applyAdmins(
        _ admins: [Lemmy.PersonView],
        siteId: Int64,
        db: Database
    ) throws {
        try SiteAdminRecord
            .filter(Column("siteId") == siteId)
            .deleteAll(db)
        for (ordinal, view) in admins.enumerated() {
            var record = SiteAdminRecord(
                siteId: siteId,
                ordinal: ordinal,
                personActorId: view.person.actor_id,
                personName: view.person.name,
                displayName: view.person.display_name,
                avatarUrl: view.person.avatar
            )
            try record.insert(db)
        }
    }

    private static func apply(
        response: Lemmy.GetSiteResponse,
        to record: inout SiteRecord,
        now: Date
    ) {
        let view = response.site_view
        record.name = view.site.name
        record.descriptionText = view.site.description
        record.sidebar = view.site.sidebar
        record.legalInformation = view.local_site.legal_information
        record.iconUrl = view.site.icon
        record.bannerUrl = view.site.banner
        record.version = response.version

        record.defaultPostListingType = view.local_site.default_post_listing_type.rawValue
        record.enableDownvotes = view.local_site.enable_downvotes
        record.enableNsfw = view.local_site.enable_nsfw

        record.numberOfPosts = Int64(view.counts.posts)
        record.numberOfComments = Int64(view.counts.comments)
        record.numberOfCommunities = Int64(view.counts.communities)
        record.numberOfUsers = Int64(view.counts.users)
        record.numberOfUsersDay = Int64(view.counts.users_active_day)
        record.numberOfUsersWeek = Int64(view.counts.users_active_week)
        record.numberOfUsersMonth = Int64(view.counts.users_active_month)
        record.numberOfUsersHalfYear = Int64(view.counts.users_active_half_year)

        record.infoCreatedDate = view.local_site.published
        record.infoUpdatedDate = view.local_site.updated

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
