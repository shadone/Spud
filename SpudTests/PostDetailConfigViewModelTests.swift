//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import Testing
@testable import Spud

/// `PreferencesService()` has no injectable storage, so this target (hosted
/// inside the `Spud` app target per `project.yml`) writes the REAL
/// `info.ddenis.Spud` `UserDefaults.standard` domain — the same one a later
/// `SpudUITests` launch reads from, and `ResetFilesystem` does not reliably
/// clear it (see `QuickSwitchViewModelTests`'s doc comment for the concrete
/// UI-test failure this caused elsewhere). Serialized, and each mutating test
/// `defer`-restores `commentDensity` to its documented default.
@MainActor
@Suite(.serialized)
struct PostDetailConfigViewModelTests {
    @Test
    func seedsFromPreferencesAndCurrentSort() {
        let prefs = PreferencesService()
        defer { prefs.commentDensity = .comfortable }
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
        defer { prefs.commentDensity = .comfortable }
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
