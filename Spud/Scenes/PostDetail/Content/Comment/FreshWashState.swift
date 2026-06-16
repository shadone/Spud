//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Which background-wash treatment a comment row should show for the
/// "new since last visit" state. Pure decision, unit-tested in isolation.
enum FreshWashState: Equatable {
    /// No wash (not new, or new but its one-time fade already played).
    case none
    /// Hold a static tint for the visit (reduce-motion: no animation).
    case staticTint
    /// Start tinted and fade to the resting background once.
    case fadeFromTint

    static func resolve(isNew: Bool, hasAnimated: Bool, reduceMotion: Bool) -> FreshWashState {
        guard isNew else { return .none }
        if reduceMotion { return .staticTint }
        return hasAnimated ? .none : .fadeFromTint
    }
}
