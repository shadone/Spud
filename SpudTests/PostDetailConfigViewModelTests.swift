//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import Testing
@testable import Spud

/// Each test builds its `PreferencesService` on a fresh, private `UserDefaults`
/// suite (`PreferencesService.ephemeral()`), so mutating `commentDensity` never
/// touches the shared `.standard` (`info.ddenis.Spud`) domain a later
/// `SpudUITests` launch reads from. That isolation removes the need for the old
/// `.serialized` + `defer`-restore workaround.
@MainActor
struct PostDetailConfigViewModelTests {
    @Test
    func seedsFromPreferencesAndCurrentSort() {
        let prefs = PreferencesService.ephemeral()
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
        let prefs = PreferencesService.ephemeral()
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
        var selected: Lemmy.CommentSortType?
        let viewModel = PostDetailConfigViewModel(
            preferencesService: PreferencesService.ephemeral(),
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )
        viewModel.selectSort(.Top)
        #expect(viewModel.currentSort == .Top)
        #expect(selected == .Top)
    }
}
