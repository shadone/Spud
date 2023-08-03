//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension TopPosts {
    static let fake = TopPosts(posts: [
        .init(
            spudUrl: URL(string: "spud://fake1")!,
            title: "Federal Reserve Calls For More Poverty",
            type: .text,
            community: .init(
                name: "economics",
                site: "the.onion"
            ),
            score: 8760,
            numberOfComments: 5432
        ),
        .init(
            spudUrl: URL(string: "spud://fake2")!,
            title: "Nintendo Unveils New Controller Designed To Be Chucked Across A Room",
            type: .text,
            community: .init(
                name: "tiktok",
                site: "the.onion"
            ),
            score: 120,
            numberOfComments: 36
        ),
        .init(
            spudUrl: URL(string: "spud://fake3")!,
            title: "SAG-AFTRA Offers Unlimited Use Of Justin Long’s AI Likeness In Exchange For Fair Contract",
            type: .text,
            community: .init(
                name: "media",
                site: "the.onion"
            ),
            score: 12345,
            numberOfComments: 42
        ),
    ])
}
