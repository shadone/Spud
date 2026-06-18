//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import XCTest
@testable import Spud

@MainActor
final class QuickSwitchViewModelTests: XCTestCase {
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

    func testSeedsFromPreferences() {
        let prefs = PreferencesService()
        prefs.postDensity = .compact
        prefs.thumbnailPosition = .right
        prefs.showVoteButtons = false

        let viewModel = makeViewModel(preferences: prefs, currentSort: .New)

        XCTAssertEqual(viewModel.postDensity, .compact)
        XCTAssertEqual(viewModel.thumbnailPosition, .right)
        XCTAssertEqual(viewModel.showVoteButtons, false)
        XCTAssertEqual(viewModel.currentSort, .New)
    }

    func testUpdatePostDensityWritesThrough() {
        let prefs = PreferencesService()
        prefs.postDensity = .comfortable
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updatePostDensity(.compact)

        XCTAssertEqual(viewModel.postDensity, .compact)
        XCTAssertEqual(prefs.postDensity, .compact)
    }

    func testUpdateThumbnailPositionWritesThrough() {
        let prefs = PreferencesService()
        prefs.thumbnailPosition = .left
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateThumbnailPosition(.hidden)

        XCTAssertEqual(viewModel.thumbnailPosition, .hidden)
        XCTAssertEqual(prefs.thumbnailPosition, .hidden)
    }

    func testUpdateShowVoteButtonsWritesThrough() {
        let prefs = PreferencesService()
        prefs.showVoteButtons = true
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateShowVoteButtons(false)

        XCTAssertEqual(viewModel.showVoteButtons, false)
        XCTAssertEqual(prefs.showVoteButtons, false)
    }

    func testSelectSortInvokesCallbackAndUpdatesCurrent() {
        let prefs = PreferencesService()
        var selected: Components.Schemas.SortType?
        let viewModel = makeViewModel(
            preferences: prefs,
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )

        viewModel.selectSort(.New)

        XCTAssertEqual(selected, .New)
        XCTAssertEqual(viewModel.currentSort, .New)
    }
}
