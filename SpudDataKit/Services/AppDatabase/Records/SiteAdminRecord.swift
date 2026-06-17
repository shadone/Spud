//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// An administrator of a Lemmy site, sourced from `GetSiteResponse.admins`.
/// One row per admin per ``SiteRecord``; `ordinal` preserves the API order
/// (ordinal 0 is treated as the site owner by the UI).
public struct SiteAdminRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "siteAdmin"

    public var id: Int64?
    public var siteId: Int64
    public var ordinal: Int
    public var personActorId: String
    public var personName: String
    public var displayName: String?
    public var avatarUrl: String?

    public init(
        id: Int64? = nil,
        siteId: Int64,
        ordinal: Int,
        personActorId: String,
        personName: String,
        displayName: String? = nil,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.siteId = siteId
        self.ordinal = ordinal
        self.personActorId = personActorId
        self.personName = personName
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

extension SiteAdminRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension SiteAdminRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let siteId = Column(CodingKeys.siteId)
        public static let ordinal = Column(CodingKeys.ordinal)
    }

    /// Human label: display name if present, else the bare username.
    var label: String {
        displayName ?? personName
    }

    /// Role label shown in the UI. Lemmy exposes no explicit owner flag, so the
    /// first admin (ordinal 0) is treated as the owner. Documented approximation.
    var roleLabel: String {
        ordinal == 0 ? "Owner" : "Admin"
    }
}
