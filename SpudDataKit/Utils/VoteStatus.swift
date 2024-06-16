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

    /// Initialize from Core Data raw value.
    init(rawValue: NSNumber?) {
        guard let isUp = rawValue?.boolValue else {
            self = .neutral
            return
        }
        self = isUp ? .up : .down
    }

    /// Raw value for storing in Core Data models.
    var rawValue: NSNumber? {
        switch self {
        case .up:
            return NSNumber(booleanLiteral: true)
        case .down:
            return NSNumber(booleanLiteral: false)
        case .neutral:
            return nil
        }
    }
}
