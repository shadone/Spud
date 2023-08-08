//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension TopPosts {
    /// Fake Top Posts object that is shown when ``IntentTimelineProvider`` asks for a snapshot.
    /// Shown to the user as a preview when adding a new widget.
    static let snapshot = TopPosts(posts: [
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/snapshot1")!,
            title: "Douglas's Squirrel",
            type: .image(URL(string: "info.ddenis.spud://image-from-assets/Snapshots/squirrel")!),
            community: .init(
                name: "aww",
                site: "lemmy.world"
            ),
            score: 147,
            numberOfComments: 7
        ),
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/snapshot2")!,
            title: "Vampires have as much of a weakness to a wooden stake through the heart as anyone else.",
            type: .text,
            community: .init(
                name: "showerthoughts",
                site: "kbin.social"
            ),
            score: 134,
            numberOfComments: 17
        ),
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/snapshot3")!,
            title: "To all the new(er) Reddit refugees!",
            type: .image(URL(string: "info.ddenis.spud://image-from-assets/Snapshots/futurama")!),
            community: .init(
                name: "futurama",
                site: "lemmy.world"
            ),
            score: 3049,
            numberOfComments: 408
        ),
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/snapshot4")!,
            title: "The Feet Issue: Where They’re Going, Where They’ve Been",
            type: .text,
            community: .init(
                name: "askscience",
                site: "the.onion"
            ),
            score: 553,
            numberOfComments: 12
        ),
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/snapshot5")!,
            title: "Marvel Not Even Bothering To Replace Green Screens With CGI Anymore",
            type: .image(URL(string: "info.ddenis.spud://image-from-assets/Snapshots/marvel")!),
            community: .init(
                name: "media",
                site: "the.onion"
            ),
            score: 996,
            numberOfComments: 654
        ),
        .init(
            spudUrl: URL(string: "info.ddenis.spud://topPosts/snapshot6")!,
            title: "European Union votes to bring back replaceable phone batteries",
            type: .image(URL(string: "info.ddenis.spud://image-from-assets/Snapshots/battery")!),
            community: .init(
                name: "technology",
                site: "beehaw.org"
            ),
            score: 852,
            numberOfComments: 296
        ),
    ])
}
