//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Community {
    static var fake: Community = .init(
        id: 1,
        name: "world",
        title: "World",
        description: "Hello world community",
        removed: false,
        published: Date(timeIntervalSince1970: 1_680_667_628),
        updated: nil,
        deleted: false,
        nsfw: false,
        actor_id: URL(string: "https://example.com/c/world")!,
        local: true,
        icon: nil,
        banner: nil,
        hidden: false,
        posting_restricted_to_mods: false,
        instance_id: 1
    )
}
