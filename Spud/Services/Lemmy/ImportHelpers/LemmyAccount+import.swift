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

        // TODO: update LemmyAccountInfo
    }
}
