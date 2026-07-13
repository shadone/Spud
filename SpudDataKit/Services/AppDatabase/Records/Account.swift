//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit

public struct AccountRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "account"

    public var id: Int64?
    public var siteId: Int64
    public var personId: Int64?
    public var accountKeychainId: String
    public var isDefault: Bool
    public var isServiceAccount: Bool
    public var isSignedOutAccountType: Bool
    public var isEphemeral: Bool
    public var localAccountId: Int64?
    public var email: String?
    public var emailVerified: Bool?
    public var acceptedApplication: Bool?
    public var defaultListingType: String?
    public var defaultSortType: String?
    public var showAvatars: Bool?
    public var showBotAccounts: Bool?
    public var showNsfw: Bool?
    public var blurNsfw: Bool?
    public var showReadPosts: Bool?
    public var showScores: Bool?
    /// The account's stored JWT was rejected as expired/revoked; the UI shows a
    /// quiet re-login hint. Cleared by any successful authed result. Always
    /// `false` for signed-out / service / ephemeral accounts.
    public var sessionNeedsReauth: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        siteId: Int64,
        personId: Int64? = nil,
        accountKeychainId: String,
        isDefault: Bool = false,
        isServiceAccount: Bool = false,
        isSignedOutAccountType: Bool = false,
        isEphemeral: Bool = false,
        localAccountId: Int64? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        acceptedApplication: Bool? = nil,
        defaultListingType: String? = nil,
        defaultSortType: String? = nil,
        showAvatars: Bool? = nil,
        showBotAccounts: Bool? = nil,
        showNsfw: Bool? = nil,
        blurNsfw: Bool? = nil,
        showReadPosts: Bool? = nil,
        showScores: Bool? = nil,
        sessionNeedsReauth: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.siteId = siteId
        self.personId = personId
        self.accountKeychainId = accountKeychainId
        self.isDefault = isDefault
        self.isServiceAccount = isServiceAccount
        self.isSignedOutAccountType = isSignedOutAccountType
        self.isEphemeral = isEphemeral
        self.localAccountId = localAccountId
        self.email = email
        self.emailVerified = emailVerified
        self.acceptedApplication = acceptedApplication
        self.defaultListingType = defaultListingType
        self.defaultSortType = defaultSortType
        self.showAvatars = showAvatars
        self.showBotAccounts = showBotAccounts
        self.showNsfw = showNsfw
        self.blurNsfw = blurNsfw
        self.showReadPosts = showReadPosts
        self.showScores = showScores
        self.sessionNeedsReauth = sessionNeedsReauth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension AccountRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension AccountRecord {
    /// Decodes the persisted `defaultSortType` raw value to its OpenAPI
    /// enum case, or `.Hot` when the column is nil or its value no longer
    /// maps to a known case.
    var resolvedDefaultSortType: Lemmy.SortType {
        guard
            let raw = defaultSortType,
            let value = Lemmy.SortType(rawValue: raw)
        else { return .Hot }
        return value
    }
}
