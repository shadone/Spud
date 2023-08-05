//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

extension LemmyPersonInfo {
    func set(from model: LocalUserView) {
        set(from: model.person)
        set(from: model.counts)

        updatedAt = Date()
    }

    func set(from model: PersonView) {
        set(from: model.person)
        set(from: model.counts)

        updatedAt = Date()
    }

    /// Partial update of the ``LemmyPersonInfo``.
    /// - Note: we do **not** touch ``updatedAt`` property here as it is only a partial update.
    func set(from model: Person) {
        name = model.name
        displayName = model.display_name
        avatarUrl = model.avatar
        personCreatedDate = model.published
        personUpdatedDate = model.updated
        actorId = model.actor_id
        bio = model.bio
        bannerUrl = model.banner
        isDeletedPerson = model.deleted
        matrixUserId = model.matrix_user_id
        isLocal = model.local
        isAdmin = model.admin
        isBotAccount = model.bot_account
        isBanned = model.banned
        banExpires = model.ban_expires
    }

    /// Partial update of the ``LemmyPersonInfo``.
    /// - Note: we do **not** touch ``updatedAt`` property here as it is only a partial update.
    private func set(from model: PersonAggregates) {
        numberOfPosts = model.post_count
        totalScoreForPosts = model.post_score
        numberOfComments = model.comment_count
        totalScoreForComments = model.comment_score
    }
}
