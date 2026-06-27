//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import Testing
@testable import Spud

@MainActor
struct PostDetailConfigViewModelTests {
    @Test
    func seedsFromPreferencesAndCurrentSort() {
        let prefs = PreferencesService()
        prefs.commentDensity = .compact
        let viewModel = PostDetailConfigViewModel(
            preferencesService: prefs,
            currentSort: .New,
            onSelectSort: { _ in }
        )
        #expect(viewModel.commentDensity == .compact)
        #expect(viewModel.currentSort == .New)
    }

    @Test
    func updateCommentDensityWritesThrough() {
        let prefs = PreferencesService()
        prefs.commentDensity = .comfortable
        let viewModel = PostDetailConfigViewModel(
            preferencesService: prefs,
            currentSort: .Hot,
            onSelectSort: { _ in }
        )
        viewModel.updateCommentDensity(.compact)
        #expect(viewModel.commentDensity == .compact)
        #expect(prefs.commentDensity == .compact)
    }

    @Test
    func selectSortRoutesAndUpdates() {
        var selected: Components.Schemas.CommentSortType?
        let viewModel = PostDetailConfigViewModel(
            preferencesService: PreferencesService(),
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )
        viewModel.selectSort(.Top)
        #expect(viewModel.currentSort == .Top)
        #expect(selected == .Top)
    }
}
