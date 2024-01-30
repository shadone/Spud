//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

public struct TopPosts: Codable {
    public let posts: [Post]

    public init(posts: [Post]) {
        self.posts = posts
    }
}

extension TopPosts {
    init(from feed: LemmyFeed) {
        let postInfos = feed.pages
            .sorted(by: { $0.index < $1.index })
            .first?
            .pageElements
            .sorted(by: { $0.index < $1.index })
            .map(\.post)
            .compactMap(\.postInfo)
            // The max number of posts widget of any size might need.
            .prefix(6) ?? []

        self = TopPosts(
            posts: postInfos
                .map { postInfo -> Post in
                    let postType: PostType
                    if let thumbnailUrl = postInfo.thumbnailUrl {
                        postType = .image(thumbnailUrl)
                    } else {
                        postType = .text
                    }

                    let postUrl = URL.SpudInternalLink.post(
                        postId: postInfo.post.postId,
                        instance: postInfo.post.account.site.instance.actorId
                    ).url

                    let community: Community
                    if let communityInfo = postInfo.community.communityInfo {
                        community = Community(
                            name: communityInfo.name,
                            site: communityInfo.instanceActorId.host
                        )
                    } else {
                        community = Community(name: "-", site: "")
                    }

                    return .init(
                        spudUrl: postUrl,
                        title: postInfo.title,
                        type: postType,
                        community: community,
                        score: postInfo.score,
                        numberOfComments: postInfo.numberOfComments
                    )
                }
        )
    }
}
