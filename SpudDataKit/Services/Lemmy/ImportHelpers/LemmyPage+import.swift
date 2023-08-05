//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit

extension LemmyPage {
    convenience init(
        _ postViews: [PostView],
        index: Int16,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        createdAt = Date()
        self.index = index

        postViews
            .enumerated()
            .forEach { index, postView in
                assert(index < Int16.max)

                let post = LemmyPost.upsert(postView, account: account, in: context)

                let element = LemmyPageElement(context: context)
                element.index = Int16(index)
                element.page = self
                element.post = post
            }
    }
}
