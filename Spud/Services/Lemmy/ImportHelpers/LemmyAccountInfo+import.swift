//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

extension LemmyAccountInfo {
    func set(from model: LocalUser) {
        localAccountId = model.id
        personId = model.person_id
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
        totp2faUrl = model.totp_2fa_url

        updatedAt = Date()
    }
}
