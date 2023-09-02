//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog

extension LemmyAccountInfo {
    func set(from model: LocalUserView) {
        set(from: model.local_user)
        person.set(from: model)
    }

    private func set(from model: LocalUser) {
        localAccountId = model.id
        email = model.email
        showNsfw = model.show_nsfw
        defaultSortType = model.default_sort_type
        defaultListingType = model.default_listing_type
        showAvatars = model.show_avatars
        showScores = model.show_scores
        showBotAccounts = model.show_bot_accounts
        showReadPosts = model.show_read_posts
        emailVerified = model.email_verified
        acceptedApplication = model.accepted_application
        totp2faUrl = model.totp_2fa_url?.url

        updatedAt = Date()
    }
}
