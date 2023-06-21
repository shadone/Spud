//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

extension LemmyComment {
    /// Describes whether the user has upvoted this comment.
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
