//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit

public struct TopPosts: Codable, Sendable {
    public let posts: [Post]

    public init(posts: [Post]) {
        self.posts = posts
    }
}

extension TopPosts {
    init(rows: [WidgetPostRow]) {
        self = TopPosts(
            posts: rows.compactMap { row -> Post? in
                guard
                    let accountInstanceUrl = URL(string: row.accountInstanceActorId),
                    let accountInstance = InstanceActorId(from: accountInstanceUrl)
                else {
                    return nil
                }

                let postType: PostType
                if
                    let thumbnailString = row.thumbnailUrl,
                    let thumbnailUrl = URL(string: thumbnailString)
                {
                    postType = .image(thumbnailUrl)
                } else {
                    postType = .text
                }

                let postUrl = URL.SpudInternalLink.post(
                    postId: Int32(truncatingIfNeeded: row.serverPostId),
                    instance: accountInstance
                ).url

                return Post(
                    spudUrl: postUrl,
                    title: row.title,
                    type: postType,
                    community: Community(name: row.communityName, site: row.communityInstanceHost),
                    score: row.score,
                    numberOfComments: row.numberOfComments
                )
            }
        )
    }
}
