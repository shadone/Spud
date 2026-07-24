//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit

/// Backs the Quick Switch popover. Reads the current feed-display preferences
/// from ``PreferencesService`` and writes changes straight back through it, so
/// the live post list (which observes the same streams) re-flows immediately.
///
/// The popover is short-lived and the only writer while open, so — unlike
/// ``PreferencesViewModel`` — it does not mirror the preference streams; it
/// seeds once at init. Sort is per-feed, so it is not a preference: selection
/// is routed back to the controller via ``onSelectSort``.
@MainActor
@Observable
final class QuickSwitchViewModel {
    private let preferencesService: PreferencesServiceType
    private let onSelectSort: (Lemmy.SortType) -> Void
    private let onDownloadForOffline: () -> Void

    let allPostDensities: [PostDensity] = PostDensity.allCases
    let allThumbnailPositions: [ThumbnailPosition] = ThumbnailPosition.allCases

    var postDensity: PostDensity
    var thumbnailPosition: ThumbnailPosition
    var showVoteButtons: Bool
    var showNsfw: Bool
    var blurNsfw: Bool
    var hasAcknowledgedNsfwAge: Bool
    var currentSort: Lemmy.SortType

    var hideReadPosts: Bool
    var hideReadPostsMode: HideReadPostsFilter.Mode

    /// The master "mark posts as read" and its scroll sub-option, tracked as raw
    /// stored prefs. The popover doesn't expose them directly — it presents the
    /// single ``markReadOnScroll`` effective toggle over them.
    private(set) var markPostsRead: Bool
    private(set) var markPostsReadOnScroll: Bool

    /// Whether posts are marked read as they scroll past — the effective state
    /// the popover's single toggle presents. Scroll marking only takes effect
    /// when the master ``markPostsRead`` is also on, so both must be true.
    var markReadOnScroll: Bool {
        markPostsRead && markPostsReadOnScroll
    }

    init(
        preferencesService: PreferencesServiceType,
        currentSort: Lemmy.SortType,
        onSelectSort: @escaping (Lemmy.SortType) -> Void,
        onDownloadForOffline: @escaping () -> Void = { }
    ) {
        self.preferencesService = preferencesService
        self.onSelectSort = onSelectSort
        self.onDownloadForOffline = onDownloadForOffline
        self.currentSort = currentSort
        postDensity = preferencesService.postDensity
        thumbnailPosition = preferencesService.thumbnailPosition
        showVoteButtons = preferencesService.showVoteButtons
        showNsfw = preferencesService.showNsfw
        blurNsfw = preferencesService.blurNsfw
        hasAcknowledgedNsfwAge = preferencesService.hasAcknowledgedNsfwAge
        hideReadPosts = preferencesService.hideReadPosts
        hideReadPostsMode = preferencesService.hideReadPostsMode
        markPostsRead = preferencesService.markPostsRead
        markPostsReadOnScroll = preferencesService.markPostsReadOnScroll
    }

    func updatePostDensity(_ value: PostDensity) {
        postDensity = value
        preferencesService.postDensity = value
        Haptics.tap()
    }

    func updateThumbnailPosition(_ value: ThumbnailPosition) {
        thumbnailPosition = value
        preferencesService.thumbnailPosition = value
        Haptics.tap()
    }

    func updateShowVoteButtons(_ value: Bool) {
        showVoteButtons = value
        preferencesService.showVoteButtons = value
        Haptics.tap()
    }

    func acknowledgeNsfwAge() {
        hasAcknowledgedNsfwAge = true
        preferencesService.hasAcknowledgedNsfwAge = true
    }

    /// Writes the NSFW preference straight through `PreferencesService`. The
    /// hosting `PostListViewController` observes `showNsfwStream`, so toggling
    /// here reloads the feed (and syncs to the server on the frontpage)
    /// automatically — no separate callback is needed.
    func updateShowNsfw(_ value: Bool) {
        showNsfw = value
        preferencesService.showNsfw = value
        Haptics.tap()
    }

    /// Writes the blur preference through `PreferencesService`. The hosting
    /// `PostListViewController` observes `blurNsfwStream`, so toggling here
    /// re-applies blur in place (and syncs to the server on the frontpage).
    func updateBlurNsfw(_ value: Bool) {
        blurNsfw = value
        preferencesService.blurNsfw = value
        Haptics.tap()
    }

    /// Toggles hiding read posts from the feed. Writes straight through
    /// `PreferencesService`; the hosting `PostListViewController` observes
    /// `hideReadPostsStream` and re-flows the visible feed live.
    func updateHideReadPosts(_ value: Bool) {
        hideReadPosts = value
        preferencesService.hideReadPosts = value
        Haptics.tap()
    }

    /// Chooses when read posts are hidden (immediately vs at the next refresh).
    /// Observed live via `hideReadPostsModeStream`.
    func updateHideReadPostsMode(_ value: HideReadPostsFilter.Mode) {
        hideReadPostsMode = value
        preferencesService.hideReadPostsMode = value
        Haptics.tap()
    }

    /// Toggles marking posts read as they scroll past. Scroll marking only takes
    /// effect while the master ``markPostsRead`` is on, so turning this on also
    /// enables the master — the popover never presents a dead, disabled toggle,
    /// and any stale "scroll on while master off" state is resolved. Turning it
    /// off leaves the master on, preserving mark-on-open.
    func updateMarkReadOnScroll(_ value: Bool) {
        markPostsReadOnScroll = value
        preferencesService.markPostsReadOnScroll = value
        if value, !markPostsRead {
            markPostsRead = true
            preferencesService.markPostsRead = true
        }
        Haptics.tap()
    }

    func selectSort(_ value: Lemmy.SortType) {
        currentSort = value
        onSelectSort(value)
        Haptics.tap()
    }

    /// Routes the "Download for offline" tap back to the hosting controller,
    /// which holds the feed handle, account scope, and download service. The
    /// popover dismisses itself; the controller presents the progress sheet.
    func downloadForOffline() {
        Haptics.tap()
        onDownloadForOffline()
    }
}
