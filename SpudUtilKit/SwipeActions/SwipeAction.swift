//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// An action that can be assigned to a swipe-gesture slot on a post or comment
/// cell. Pure data: the UI layer maps each case to an SF Symbol, a tint colour,
/// a (state-aware) title, and a handler.
///
/// `.collapse` is comment-only; `.none` leaves the slot empty (the swipe in
/// that direction/depth does nothing). Decoding is forgiving — an unknown raw
/// value (e.g. an action removed in a future build) decodes to `.none` rather
/// than throwing, so a stored config never fails to load.
public enum SwipeAction: String, Codable, CaseIterable, Sendable, Identifiable {
    /// No action; the slot is empty.
    case none

    /// Upvote (or remove an existing upvote) the post / comment.
    case upvote

    /// Downvote (or remove an existing downvote) the post / comment.
    case downvote

    /// Toggle the saved state of the post / comment.
    case save

    /// Open the composer to reply to the post / comment.
    case reply

    /// Share the post's / comment's canonical URL.
    case share

    /// Collapse or expand a comment thread. Comment-only.
    case collapse

    public var id: String {
        rawValue
    }

    /// Forgiving decode: an unrecognised stored value (e.g. an action that no
    /// longer exists) maps to `.none` instead of failing the whole config.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SwipeAction(rawValue: raw) ?? .none
    }

    /// Whether this action is meaningful for the given content kind. `.collapse`
    /// only applies to comments; everything else applies to both.
    public func isValid(for kind: SwipeActionContentKind) -> Bool {
        switch self {
        case .collapse:
            return kind == .comment
        case .none, .upvote, .downvote, .save, .reply, .share:
            return true
        }
    }
}

/// The kind of cell a ``SwipeActionConfig`` drives. Some actions (notably
/// `.collapse`) are only valid for one kind.
public enum SwipeActionContentKind: String, Codable, Sendable {
    case post
    case comment

    /// Every action assignable for this content kind, in a stable menu order.
    public var assignableActions: [SwipeAction] {
        SwipeAction.allCases.filter { $0.isValid(for: self) }
    }
}
