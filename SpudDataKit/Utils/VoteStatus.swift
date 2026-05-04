//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public enum VoteStatus: Sendable {
    /// Upvoted.
    case up
    /// Downvoted.
    case down
    /// Not voted.
    case neutral

    public var isUp: Bool {
        if case .up = self {
            return true
        }
        return false
    }

    public var isDown: Bool {
        if case .down = self {
            return true
        }
        return false
    }
}
