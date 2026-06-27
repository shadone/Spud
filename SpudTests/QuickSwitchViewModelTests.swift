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
struct QuickSwitchViewModelTests {
    private func makeViewModel(
        preferences: PreferencesService,
        currentSort: Components.Schemas.SortType = .Hot,
        onSelectSort: @escaping (Components.Schemas.SortType) -> Void = { _ in }
    ) -> QuickSwitchViewModel {
        QuickSwitchViewModel(
            preferencesService: preferences,
            currentSort: currentSort,
            onSelectSort: onSelectSort
        )
    }

    @Test
    func seedsFromPreferences() {
        let prefs = PreferencesService()
        prefs.postDensity = .compact
        prefs.thumbnailPosition = .right
        prefs.showVoteButtons = false

        let viewModel = makeViewModel(preferences: prefs, currentSort: .New)

        #expect(viewModel.postDensity == .compact)
        #expect(viewModel.thumbnailPosition == .right)
        #expect(viewModel.showVoteButtons == false)
        #expect(viewModel.currentSort == .New)
    }

    @Test
    func updatePostDensityWritesThrough() {
        let prefs = PreferencesService()
        prefs.postDensity = .comfortable
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updatePostDensity(.compact)

        #expect(viewModel.postDensity == .compact)
        #expect(prefs.postDensity == .compact)
    }

    @Test
    func updateThumbnailPositionWritesThrough() {
        let prefs = PreferencesService()
        prefs.thumbnailPosition = .left
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateThumbnailPosition(.hidden)

        #expect(viewModel.thumbnailPosition == .hidden)
        #expect(prefs.thumbnailPosition == .hidden)
    }

    @Test
    func updateShowVoteButtonsWritesThrough() {
        let prefs = PreferencesService()
        prefs.showVoteButtons = true
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateShowVoteButtons(false)

        #expect(viewModel.showVoteButtons == false)
        #expect(prefs.showVoteButtons == false)
    }

    @Test
    func updateShowNsfwWritesThrough() {
        let prefs = PreferencesService()
        prefs.showNsfw = false
        let viewModel = makeViewModel(preferences: prefs)
        #expect(viewModel.showNsfw == false)

        viewModel.updateShowNsfw(true)

        #expect(viewModel.showNsfw == true)
        #expect(prefs.showNsfw == true)
    }

    @Test
    func selectSortInvokesCallbackAndUpdatesCurrent() {
        let prefs = PreferencesService()
        var selected: Components.Schemas.SortType?
        let viewModel = makeViewModel(
            preferences: prefs,
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )

        viewModel.selectSort(.New)

        #expect(selected == .New)
        #expect(viewModel.currentSort == .New)
    }
}
