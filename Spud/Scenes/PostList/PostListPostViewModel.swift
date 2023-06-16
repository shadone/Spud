//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

class PostListPostViewModel {
    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        post.publisher(for: \.title)
            .map { AttributedString($0) }
            .eraseToAnyPublisher()
    }

    var communityName: AnyPublisher<AttributedString, Never> {
        post.publisher(for: \.communityName)
            .map { AttributedString($0) }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private let post: LemmyPost

    // MARK: Functions

    init(post: LemmyPost) {
        self.post = post
    }
}
