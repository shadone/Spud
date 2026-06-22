//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Pure math translating a desired absolute vote into the local DB field
/// changes the optimistic UI needs. Save/hide are direct boolean writes and do
/// not need a projection helper.
public enum OutboxProjection {
    public static func voteStatus(fromDB raw: Int64?) -> VoteStatus {
        switch raw {
        case 1: .up
        case 0: .down
        default: .neutral
        }
    }

    public static func dbVoteStatus(for status: LikeStatus) -> Int64? {
        switch status {
        case .liked: 1
        case .disliked: 0
        case .neutral: nil
        }
    }

    public static func contribution(_ status: VoteStatus) -> Int64 {
        switch status {
        case .up: 1
        case .down: -1
        case .neutral: 0
        }
    }

    /// Score change when moving from the current DB vote to `desired`.
    /// `LikeStatus.rawValue` already equals the contribution of the target vote.
    public static func voteScoreDelta(currentDB raw: Int64?, desired: LikeStatus) -> Int64 {
        Int64(desired.rawValue) - contribution(voteStatus(fromDB: raw))
    }
}
