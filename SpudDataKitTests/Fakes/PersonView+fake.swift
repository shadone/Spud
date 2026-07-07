//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.PersonView {
    static func fake(
        person: Lemmy.Person = .fake,
        isAdmin: Bool = false
    ) -> Lemmy.PersonView {
        .init(
            person: person,
            counts: .init(
                person_id: person.id,
                post_count: 0,
                comment_count: 0
            ),
            is_admin: isAdmin
        )
    }
}
