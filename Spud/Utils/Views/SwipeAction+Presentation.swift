//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import UIKit

/// State a cell exposes to the swipe-action presentation layer so titles and
/// icons can reflect the current toggle (saved/unsaved, collapsed/expanded,
/// upvoted/not). All optional — a kind that doesn't have a given state leaves
/// it nil and the default (non-toggled) presentation is used.
struct SwipeActionState {
    var isSaved: Bool = false
    var isUpvoted: Bool = false
    var isDownvoted: Bool = false
    var isCollapsed: Bool = false
}

/// Maps a pure ``SwipeAction`` to its on-screen presentation (SF Symbol, tint,
/// accessible title), given the cell's current state and the shared appearance
/// for the vote glyphs/colours. Lives in the app layer because it depends on
/// UIKit and `GeneralAppearance`; the model itself stays pure in SpudUtilKit.
extension SwipeAction {
    /// The SF Symbol image for this action in `state`. Returns nil for `.none`.
    func image(state: SwipeActionState, appearance: GeneralAppearance) -> UIImage? {
        switch self {
        case .none:
            return nil
        case .upvote:
            return appearance.upvoteIcon
        case .downvote:
            return appearance.downvoteIcon
        case .save:
            return UIImage(systemName: state.isSaved ? "bookmark.slash" : "bookmark")
        case .reply:
            return UIImage(systemName: "arrowshape.turn.up.backward")
        case .share:
            return UIImage(systemName: "square.and.arrow.up")
        case .collapse:
            return UIImage(
                systemName: state.isCollapsed
                    ? "arrow.up.left.and.arrow.down.right"
                    : "arrow.down.right.and.arrow.up.left"
            )
        }
    }

    /// The swipe-track background tint for this action.
    func backgroundColor(appearance: GeneralAppearance) -> UIColor {
        switch self {
        case .none:
            return .clear
        case .upvote:
            return appearance.upvoteSwipeActionBackgroundColor
        case .downvote:
            return appearance.downvoteSwipeActionBackgroundColor
        case .save:
            return .systemYellow
        case .reply:
            return .systemBlue
        case .share:
            return .systemTeal
        case .collapse:
            return .systemIndigo
        }
    }

    /// A state-aware, localized title (used for accessibility / future menus).
    func title(state: SwipeActionState) -> String {
        switch self {
        case .none:
            return ""
        case .upvote:
            return state.isUpvoted
                ? NSLocalizedString("Remove vote", comment: "Swipe action: remove an existing upvote")
                : NSLocalizedString("Upvote", comment: "Swipe action: upvote")
        case .downvote:
            return state.isDownvoted
                ? NSLocalizedString("Remove vote", comment: "Swipe action: remove an existing downvote")
                : NSLocalizedString("Downvote", comment: "Swipe action: downvote")
        case .save:
            return state.isSaved
                ? NSLocalizedString("Unsave", comment: "Swipe action: unsave")
                : NSLocalizedString("Save", comment: "Swipe action: save")
        case .reply:
            return NSLocalizedString("Reply", comment: "Swipe action: reply")
        case .share:
            return NSLocalizedString("Share", comment: "Swipe action: share")
        case .collapse:
            return state.isCollapsed
                ? NSLocalizedString("Expand", comment: "Swipe action: expand a collapsed comment")
                : NSLocalizedString("Collapse", comment: "Swipe action: collapse a comment")
        }
    }

    /// A short, user-facing label for the settings picker (state-independent).
    var pickerTitle: String {
        switch self {
        case .none:
            return NSLocalizedString("None", comment: "Swipe action picker: no action")
        case .upvote:
            return NSLocalizedString("Upvote", comment: "Swipe action picker: upvote")
        case .downvote:
            return NSLocalizedString("Downvote", comment: "Swipe action picker: downvote")
        case .save:
            return NSLocalizedString("Save", comment: "Swipe action picker: save")
        case .reply:
            return NSLocalizedString("Reply", comment: "Swipe action picker: reply")
        case .share:
            return NSLocalizedString("Share", comment: "Swipe action picker: share")
        case .collapse:
            return NSLocalizedString("Collapse", comment: "Swipe action picker: collapse")
        }
    }

    /// The SF Symbol used to represent the action in the settings picker.
    var pickerSystemImageName: String {
        switch self {
        case .none: return "circle.slash"
        case .upvote: return "arrow.up"
        case .downvote: return "arrow.down"
        case .save: return "bookmark"
        case .reply: return "arrowshape.turn.up.backward"
        case .share: return "square.and.arrow.up"
        case .collapse: return "arrow.down.right.and.arrow.up.left"
        }
    }
}

extension SwipeActionSlot {
    /// The corresponding trigger emitted by `SwipeActionView`.
    var trigger: SwipeActionView.ActionTrigger {
        switch self {
        case .leadingPrimary: return .leadingPrimary
        case .leadingSecondary: return .leadingSecondary
        case .trailingPrimary: return .trailingPrimary
        case .trailingSecondary: return .trailingSecondary
        }
    }

    /// The slot a `SwipeActionView` trigger maps back to.
    init(trigger: SwipeActionView.ActionTrigger) {
        switch trigger {
        case .leadingPrimary: self = .leadingPrimary
        case .leadingSecondary: self = .leadingSecondary
        case .trailingPrimary: self = .trailingPrimary
        case .trailingSecondary: self = .trailingSecondary
        }
    }
}

extension SwipeActionConfig {
    /// Builds the `SwipeActionView.Configuration` that drives the custom swipe
    /// view, mapping each slot's action to its image + tint for `state`.
    ///
    /// `SwipeActionView.Configuration` requires all four slots, so a `.none`
    /// slot is rendered with a transparent track and no image; pair this with
    /// `resolveSlot` to skip firing a handler for empty slots.
    func viewConfiguration(
        state: SwipeActionState,
        appearance: GeneralAppearance
    ) -> SwipeActionView.Configuration {
        func action(_ slot: SwipeActionSlot) -> SwipeActionView.Configuration.Action {
            let swipeAction = self.action(for: slot)
            return SwipeActionView.Configuration.Action(
                image: swipeAction.image(state: state, appearance: appearance)
                    ?? UIImage(systemName: "circle.slash")!,
                backgroundColor: swipeAction.backgroundColor(appearance: appearance),
                title: swipeAction.title(state: state)
            )
        }
        return SwipeActionView.Configuration(
            leadingPrimaryAction: action(.leadingPrimary),
            leadingSecondaryAction: action(.leadingSecondary),
            trailingPrimaryAction: action(.trailingPrimary),
            trailingSecondaryAction: action(.trailingSecondary)
        )
    }
}
