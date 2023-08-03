//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct Post: Codable, Identifiable {
    public enum PostType: Codable {
        case text
        case image(URL)

        public var imageUrl: URL? {
            if case let .image(url) = self {
                return url
            }
            return nil
        }
    }

    public var id: String { spudUrl.absoluteString }

    public let spudUrl: URL
    public let title: String
    public let type: PostType
    public let community: Community
    public let score: Int64
    public let numberOfComments: Int64

    public init(
        spudUrl: URL,
        title: String,
        type: Post.PostType,
        community: Community,
        score: Int64,
        numberOfComments: Int64
    ) {
        self.spudUrl = spudUrl
        self.title = title
        self.type = type
        self.community = community
        self.score = score
        self.numberOfComments = numberOfComments
    }
}
