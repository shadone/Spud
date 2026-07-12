//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.PersonView {
    /// A fake neutral ``LemmyKit/PersonView``. The old `PersonAggregates` nesting is
    /// gone — post/comment counts live on the neutral ``LemmyKit/Person`` now, so the
    /// view just composes the person with its admin/ban standing.
    static func fake(
        person: Lemmy.Person = .fake,
        isAdmin: Bool = false
    ) -> Lemmy.PersonView {
        .init(
            person: person,
            isAdmin: isAdmin
        )
    }
}
