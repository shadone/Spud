//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import os.log

extension LemmyCommunityInfo {
    /// Updates community info from the given full ``CommunityView`` object.
    func set(from model: CommunityView) {
        set(from: model.community)
        set(from: model.counts)
        // TODO: model.blocks and model.subscribed

        updatedAt = Date()
    }

    /// Partial update of the ``LemmyCommunityInfo``.
    /// - Note: we do **not** touch ``updatedAt`` property here as it is only a partial update.
    func set(from model: Community) {
        name = model.name
        title = model.title
        descriptionText = model.description
        isRemoved = model.removed
        communityCreatedDate = model.published
        communityUpdatedDate = model.updated
        isNsfw = model.nsfw
        actorId = model.actor_id
        isLocal = model.local
        icon = model.icon?.url
        banner = model.banner?.url
        isHidden = model.hidden
        isPostingRestrictedToMods = model.posting_restricted_to_mods
    }

    /// Partial update of the ``LemmyCommunityInfo``.
    /// - Note: we do **not** touch ``updatedAt`` property here as it is only a partial update.
    private func set(from model: CommunityAggregates) {
        // TODO:
    }
}
