//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// One of the four assignable swipe slots on a cell. Naming mirrors the custom
/// `SwipeActionView`'s gesture model: a short swipe triggers the *primary*
/// slot for its direction, a long (deep) swipe triggers the *secondary* slot.
public enum SwipeActionSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Leading direction, short swipe.
    case leadingPrimary

    /// Leading direction, long (deep) swipe.
    case leadingSecondary

    /// Trailing direction, short swipe.
    case trailingPrimary

    /// Trailing direction, long (deep) swipe.
    case trailingSecondary

    public var id: String {
        rawValue
    }
}

/// The user-configurable mapping of the four swipe slots to ``SwipeAction``s
/// for a single content kind (posts or comments).
///
/// Codable as a small JSON object so it can be persisted through
/// `@UserDefaultsBacked`. Decoding tolerates missing keys (slot defaults to
/// `.none`) and, via ``sanitized(for:)``, invalid action/kind pairings.
public struct SwipeActionConfig: Codable, Equatable, Sendable {
    public var leadingPrimary: SwipeAction
    public var leadingSecondary: SwipeAction
    public var trailingPrimary: SwipeAction
    public var trailingSecondary: SwipeAction

    public init(
        leadingPrimary: SwipeAction,
        leadingSecondary: SwipeAction,
        trailingPrimary: SwipeAction,
        trailingSecondary: SwipeAction
    ) {
        self.leadingPrimary = leadingPrimary
        self.leadingSecondary = leadingSecondary
        self.trailingPrimary = trailingPrimary
        self.trailingSecondary = trailingSecondary
    }

    /// Missing keys decode to `.none` so an older / partial stored blob still
    /// loads. (`SwipeAction`'s own decoder already maps unknown values to
    /// `.none`.)
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leadingPrimary = try container.decodeIfPresent(SwipeAction.self, forKey: .leadingPrimary) ?? .none
        leadingSecondary = try container.decodeIfPresent(SwipeAction.self, forKey: .leadingSecondary) ?? .none
        trailingPrimary = try container.decodeIfPresent(SwipeAction.self, forKey: .trailingPrimary) ?? .none
        trailingSecondary = try container.decodeIfPresent(SwipeAction.self, forKey: .trailingSecondary) ?? .none
    }

    /// The action assigned to `slot`.
    public func action(for slot: SwipeActionSlot) -> SwipeAction {
        switch slot {
        case .leadingPrimary: return leadingPrimary
        case .leadingSecondary: return leadingSecondary
        case .trailingPrimary: return trailingPrimary
        case .trailingSecondary: return trailingSecondary
        }
    }

    /// Assigns `action` to `slot`, returning a new config.
    public func setting(_ action: SwipeAction, for slot: SwipeActionSlot) -> SwipeActionConfig {
        var copy = self
        switch slot {
        case .leadingPrimary: copy.leadingPrimary = action
        case .leadingSecondary: copy.leadingSecondary = action
        case .trailingPrimary: copy.trailingPrimary = action
        case .trailingSecondary: copy.trailingSecondary = action
        }
        return copy
    }

    /// A copy with any action that is invalid for `kind` (e.g. `.collapse` on a
    /// post) demoted to `.none`. Apply before driving a cell so an unsupported
    /// pairing degrades gracefully instead of triggering a no-op handler.
    public func sanitized(for kind: SwipeActionContentKind) -> SwipeActionConfig {
        func valid(_ action: SwipeAction) -> SwipeAction {
            action.isValid(for: kind) ? action : .none
        }
        return SwipeActionConfig(
            leadingPrimary: valid(leadingPrimary),
            leadingSecondary: valid(leadingSecondary),
            trailingPrimary: valid(trailingPrimary),
            trailingSecondary: valid(trailingSecondary)
        )
    }
}

public extension SwipeActionConfig {
    /// Default post swipe actions, reproducing the behaviour shipped before M8:
    /// short leading swipe upvotes, deep leading swipe downvotes; short trailing
    /// swipe replies, deep trailing swipe saves.
    static let defaultPosts = SwipeActionConfig(
        leadingPrimary: .upvote,
        leadingSecondary: .downvote,
        trailingPrimary: .reply,
        trailingSecondary: .save
    )

    /// Default comment swipe actions, reproducing the behaviour shipped before
    /// M8: short leading swipe upvotes, deep leading swipe downvotes; short
    /// trailing swipe replies, deep trailing swipe collapses the thread.
    static let defaultComments = SwipeActionConfig(
        leadingPrimary: .upvote,
        leadingSecondary: .downvote,
        trailingPrimary: .reply,
        trailingSecondary: .collapse
    )

    /// The shipped default for the given content kind.
    static func `default`(for kind: SwipeActionContentKind) -> SwipeActionConfig {
        switch kind {
        case .post: return defaultPosts
        case .comment: return defaultComments
        }
    }
}
