//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

extension LemmyPostInfo {
    /// Describes whether the user has upvoted this post.
    var voteStatus: VoteStatus {
        get {
            VoteStatus(rawValue: voteStatusRawValue)
        }
        set {
            voteStatusRawValue = newValue.rawValue
        }
    }

    /// Publisher for ``voteStatus``.
    var voteStatusPublisher: AnyPublisher<VoteStatus, Never> {
        publisher(for: \.voteStatusRawValue)
            .map { VoteStatus(rawValue: $0) }
            .eraseToAnyPublisher()
    }
}
