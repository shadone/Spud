//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Why the post-detail screen shows the "content unavailable" placeholder
/// instead of the post. Drives the placeholder copy + glyph.
enum PostUnavailableReason: Equatable {
    /// The server rejected the request (`couldnt_find_post`); we do not know why.
    case unavailable
    /// The server returned the post marked removed by a moderator.
    case removed
    /// The server returned the post marked deleted by its author.
    case deleted

    var title: String {
        switch self {
        case .unavailable:
            return NSLocalizedString("This post is no longer available", comment: "Placeholder title: post 404s on the server")
        case .removed:
            return NSLocalizedString("Removed by moderator", comment: "Placeholder title: post removed by a moderator")
        case .deleted:
            return NSLocalizedString("Deleted by author", comment: "Placeholder title: post deleted by its author")
        }
    }

    var subtitle: String? {
        switch self {
        case .unavailable:
            return NSLocalizedString("It may have been removed.", comment: "Placeholder subtitle for an unavailable post")
        case .removed, .deleted:
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .unavailable: return "exclamationmark.octagon"
        case .removed: return "trash.slash"
        case .deleted: return "trash"
        }
    }

    /// The placeholder to show for a post-detail header, or `nil` to keep
    /// showing the content. Moderators keep seeing removed posts (they can
    /// Restore); authors keep seeing their own deleted posts (they can Restore).
    ///
    /// `moderationCapabilityResolved` guards a race: the moderation capability
    /// is fetched asynchronously, but the header row arrives from a fast local
    /// read. Until the capability is known we cannot tell a privileged viewer
    /// from a plain one, so we DEFER the removed/deleted decision (return nil,
    /// keep showing content) rather than risk hiding a removable post from a
    /// moderator or author. `.unavailable` (a server `couldnt_find_post`) does
    /// not depend on privilege, so it is surfaced immediately.
    static func forHeader(
        isRemoved: Bool,
        isDeleted: Bool,
        isUnavailable: Bool,
        canModerate: Bool,
        isOwnPost: Bool,
        moderationCapabilityResolved: Bool
    ) -> PostUnavailableReason? {
        if isUnavailable { return .unavailable }
        guard moderationCapabilityResolved else { return nil }
        if isRemoved { return canModerate ? nil : .removed }
        if isDeleted { return (isOwnPost || canModerate) ? nil : .deleted }
        return nil
    }
}
