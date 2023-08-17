//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

extension LemmyAccount {
    func upsert(
        myUserInfo model: MyUserInfo?
    ) {
        assert(
            (isSignedOutAccountType && model == nil) ||
            (!isSignedOutAccountType && model != nil)
        )
        guard let model else { return }

        guard let context = managedObjectContext else {
            assertionFailure()
            return
        }

        func createAccountInfo() -> LemmyAccountInfo {
            let accountInfo = LemmyAccountInfo(
                personId: model.local_user_view.local_user.person_id,
                in: context
            )
            accountInfo.account = self
            accountInfo.person.site = site
            return accountInfo
        }

        let accountInfo = self.accountInfo ?? createAccountInfo()
        self.accountInfo = accountInfo

        accountInfo.set(from: model.local_user_view)
        // TODO: handle model.follows: [CommunityFollowerView]
        // TODO: handle model.moderates: [CommunityModeratorView]
        // TODO: handle model.community_blocks: [CommunityBlockView]
        // TODO: handle model.person_blocks: [PersonBlockView]
        // TODO: handle model.discussion_languages: [LanguageId]
    }
}
