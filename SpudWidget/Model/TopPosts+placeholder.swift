//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension TopPosts {
    static let placeholder = TopPosts(posts: [
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/placeholder1")!,
            title: "-",
            type: .text,
            community: .init(
                name: "-",
                site: "-"
            ),
            score: 0,
            numberOfComments: 0
        ),
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/placeholder2")!,
            title: "-",
            type: .text,
            community: .init(
                name: "-",
                site: "-"
            ),
            score: 0,
            numberOfComments: 0
        ),
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/placeholder3")!,
            title: "-",
            type: .text,
            community: .init(
                name: "-",
                site: "-"
            ),
            score: 0,
            numberOfComments: 0
        ),
    ])
}
