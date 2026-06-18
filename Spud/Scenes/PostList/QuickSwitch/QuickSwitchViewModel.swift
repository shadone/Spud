//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
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
    private let onSelectSort: (Components.Schemas.SortType) -> Void

    let allPostDensities: [PostDensity] = PostDensity.allCases
    let allThumbnailPositions: [ThumbnailPosition] = ThumbnailPosition.allCases

    var postDensity: PostDensity
    var thumbnailPosition: ThumbnailPosition
    var showVoteButtons: Bool
    var currentSort: Components.Schemas.SortType

    init(
        preferencesService: PreferencesServiceType,
        currentSort: Components.Schemas.SortType,
        onSelectSort: @escaping (Components.Schemas.SortType) -> Void
    ) {
        self.preferencesService = preferencesService
        self.onSelectSort = onSelectSort
        self.currentSort = currentSort
        postDensity = preferencesService.postDensity
        thumbnailPosition = preferencesService.thumbnailPosition
        showVoteButtons = preferencesService.showVoteButtons
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

    func selectSort(_ value: Components.Schemas.SortType) {
        currentSort = value
        onSelectSort(value)
        Haptics.tap()
    }
}
