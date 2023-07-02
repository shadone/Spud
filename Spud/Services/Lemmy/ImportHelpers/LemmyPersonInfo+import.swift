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
        name = model.person.name
        displayName = model.person.display_name
        avatarUrl = model.person.avatar
        accountCreationDate = model.person.published
        actorId = model.person.actor_id
        bio = model.person.bio
        bannerUrl = model.person.banner
        isDeletedPerson = model.person.deleted
        matrixUserId = model.person.matrix_user_id
        isAdmin = model.person.admin
        isBotAccount = model.person.bot_account
        isBanned = model.person.banned
        banExpires = model.person.ban_expires

        updatedAt = Date()
    }
}
