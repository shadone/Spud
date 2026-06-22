//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit

/// Backs the post-detail config popover. Comment density is a preference,
/// written straight back through ``PreferencesService`` so the open post
/// re-flows live (the controller observes the same stream). Comment sort is
/// per-post, so it is routed to the controller via ``onSelectSort`` rather than
/// persisted. Seeds once at init (the popover is short-lived and the only writer
/// while open), mirroring ``QuickSwitchViewModel``.
@MainActor
@Observable
final class PostDetailConfigViewModel {
    private let preferencesService: PreferencesServiceType
    private let onSelectSort: (Components.Schemas.CommentSortType) -> Void

    let allCommentDensities: [PostDensity] = PostDensity.allCases

    var commentDensity: PostDensity
    var currentSort: Components.Schemas.CommentSortType

    init(
        preferencesService: PreferencesServiceType,
        currentSort: Components.Schemas.CommentSortType,
        onSelectSort: @escaping (Components.Schemas.CommentSortType) -> Void
    ) {
        self.preferencesService = preferencesService
        self.onSelectSort = onSelectSort
        self.currentSort = currentSort
        commentDensity = preferencesService.commentDensity
    }

    func updateCommentDensity(_ value: PostDensity) {
        commentDensity = value
        preferencesService.commentDensity = value
        Haptics.tap()
    }

    func selectSort(_ value: Components.Schemas.CommentSortType) {
        currentSort = value
        onSelectSort(value)
        Haptics.tap()
    }
}
