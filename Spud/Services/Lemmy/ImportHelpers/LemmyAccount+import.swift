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
            let accountInfo = LemmyAccountInfo(in: context)
            accountInfo.account = self
            return accountInfo
        }

        let accountInfo = self.accountInfo ?? createAccountInfo()
        self.accountInfo = accountInfo

        accountInfo.set(from: model.local_user_view.local_user)
    }
}
