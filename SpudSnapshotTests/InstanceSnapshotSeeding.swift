//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
@testable import Spud

/// Seeds an instance + site + admins + communities into an in-memory `AppDatabase`
/// so the synchronous cache-first render in the VCs shows populated data at snapshot
/// time. Shared between `InstanceDetailSnapshotTests` and `InstanceExploreSnapshotTests`.
///
/// - Parameters:
///   - record: The fixture whose `baseurl` / `url` identify the instance.
///   - database: The in-memory `AppDatabase` to seed.
///   - adminCount: Number of admin rows to insert (0 → anonymous/unavailable state).
///   - communityCount: Number of community directory rows to insert (0 → unavailable).
///   - sidebar: Optional sidebar markdown.
func seedInstanceSnapshot(
    _ record: ExplorerInstanceRecord,
    into database: AppDatabase,
    adminCount: Int,
    communityCount: Int,
    sidebar: String? = nil
) throws {
    let actorId = record.url ?? "https://\(record.baseurl)"
    try database.writer.write { db in
        var instance = InstanceRecord(actorId: actorId)
        try instance.insert(db)
        let instanceId = instance.id!

        var site = SiteRecord(
            instanceId: instanceId,
            name: record.name,
            sidebar: sidebar
        )
        try site.insert(db)
        let siteId = site.id!

        for ordinal in 0..<adminCount {
            var admin = SiteAdminRecord(
                siteId: siteId,
                ordinal: ordinal,
                personActorId: "\(actorId)/u/admin\(ordinal)",
                personName: "admin\(ordinal)",
                displayName: ordinal == 0 ? "Owner Admin" : "Mod Admin \(ordinal)"
            )
            try admin.insert(db)
        }

        for i in 0..<communityCount {
            var community = ExplorerCommunityRecord(
                url: "https://\(record.baseurl)/c/community\(i)",
                baseurl: record.baseurl,
                name: "community\(i)",
                title: "Community \(i) on \(record.name)",
                numberOfSubscribers: Int64(1000 - i * 100),
                score: Double(communityCount - i)
            )
            try community.insert(db)
        }
    }
}
