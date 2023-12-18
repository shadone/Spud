//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog

extension LemmyPersonInfo {
    func set(from model: LocalUserView) {
        set(from: model.person)
        set(from: model.counts)
        // "is_admin" is only exposed in PersonView
        // so we can know if another person is an admin,
        // but we cannot know if the current user is an admin.
        // ¯\_(ツ)_/¯
        isAdmin = false

        updatedAt = Date()
    }

    func set(from model: PersonView) {
        set(from: model.person)
        set(from: model.counts)
        isAdmin = model.is_admin

        updatedAt = Date()
    }

    /// Partial update of the ``LemmyPersonInfo``.
    /// - Note: we do **not** touch ``updatedAt`` property here as it is only a partial update.
    func set(from model: Person) {
        name = model.name
        displayName = model.display_name
        avatarUrl = model.avatar?.url
        personCreatedDate = model.published
        personUpdatedDate = model.updated
        actorId = model.actor_id
        bio = model.bio
        bannerUrl = model.banner?.url
        isDeletedPerson = model.deleted
        matrixUserId = model.matrix_user_id
        isLocal = model.local
        isBotAccount = model.bot_account
        isBanned = model.banned
        banExpires = model.ban_expires
    }

    /// Partial update of the ``LemmyPersonInfo``.
    /// - Note: we do **not** touch ``updatedAt`` property here as it is only a partial update.
    private func set(from model: PersonAggregates) {
        numberOfPosts = model.post_count
        numberOfComments = model.comment_count
    }
}
