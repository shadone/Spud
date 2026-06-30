//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// A snapshot of the currently-editable profile for the signed-in account: the
/// display name / bio / avatar that live on the account's own `PersonRecord`
/// together with the synced preference flags and default feed that live on the
/// `AccountRecord`. Returned by ``AppDatabase/accountEditableProfileSync(forKeychainId:)``
/// to seed the Edit Profile editor, and pushed back via `saveUserSettings`.
public struct AccountEditableProfile: Sendable, Equatable {
    public var displayName: String
    public var bio: String
    public var avatarUrl: String?
    public var bannerUrl: String?
    /// The account's local username (`name`), shown read-only in the editor.
    public var name: String
    public var showScores: Bool
    public var showBotAccounts: Bool
    public var showReadPosts: Bool
    public var showAvatars: Bool
    public var defaultListingType: Components.Schemas.ListingType

    public init(
        displayName: String,
        bio: String,
        avatarUrl: String?,
        bannerUrl: String?,
        name: String,
        showScores: Bool,
        showBotAccounts: Bool,
        showReadPosts: Bool,
        showAvatars: Bool,
        defaultListingType: Components.Schemas.ListingType
    ) {
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.name = name
        self.showScores = showScores
        self.showBotAccounts = showBotAccounts
        self.showReadPosts = showReadPosts
        self.showAvatars = showAvatars
        self.defaultListingType = defaultListingType
    }
}
