//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Person {
    static var fake: Person = .init(
        id: 1,
        name: "one",
        display_name: "One",
        avatar: nil,
        banned: false,
        published: Date(timeIntervalSince1970: 1_683_349_689),
        updated: nil,
        actor_id: URL(string: "https://example.com/u/one")!,
        bio: nil,
        local: true,
        banner: nil,
        deleted: false,
        matrix_user_id: nil,
        admin: false,
        bot_account: false,
        ban_expires: nil,
        instance_id: 1
    )
}
