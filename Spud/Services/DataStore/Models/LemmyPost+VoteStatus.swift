//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

extension LemmyPost {
    /// Describes whether the user has upvoted this post.
    /// - Tag: voteStatus
    var voteStatus: VoteStatus {
        get {
            VoteStatus(rawValue: voteStatusRawValue)
        }
        set {
            voteStatusRawValue = newValue.rawValue
        }
    }

    /// Publisher for [voteStatus](x-source-tag://voteStatus)
    var voteStatusPublisher: AnyPublisher<VoteStatus, Never> {
        publisher(for: \.voteStatusRawValue)
            .map { VoteStatus(rawValue: $0) }
            .eraseToAnyPublisher()
    }
}
