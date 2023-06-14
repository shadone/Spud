//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit

extension LemmyFeed {
    func append(contentsOf postViews: [PostView]) {
        guard let context = managedObjectContext else {
            assertionFailure()
            return
        }
        let page = LemmyPage(
            postViews,
            index: Int16(pages.count),
            in: context
        )
        addToPages(page)
    }
}
