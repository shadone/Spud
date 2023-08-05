//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct TopPosts: Codable {
    public let posts: [Post]

    public init(posts: [Post]) {
        self.posts = posts
    }
}
