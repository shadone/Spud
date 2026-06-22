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
final class PostDetailConfigViewModelTests: XCTestCase {
    func testSeedsFromPreferencesAndCurrentSort() {
        let prefs = PreferencesService()
        prefs.commentDensity = .compact
        let viewModel = PostDetailConfigViewModel(
            preferencesService: prefs,
            currentSort: .New,
            onSelectSort: { _ in }
        )
        XCTAssertEqual(viewModel.commentDensity, .compact)
        XCTAssertEqual(viewModel.currentSort, .New)
    }

    func testUpdateCommentDensityWritesThrough() {
        let prefs = PreferencesService()
        prefs.commentDensity = .comfortable
        let viewModel = PostDetailConfigViewModel(
            preferencesService: prefs,
            currentSort: .Hot,
            onSelectSort: { _ in }
        )
        viewModel.updateCommentDensity(.compact)
        XCTAssertEqual(viewModel.commentDensity, .compact)
        XCTAssertEqual(prefs.commentDensity, .compact)
    }

    func testSelectSortRoutesAndUpdates() {
        var selected: Components.Schemas.CommentSortType?
        let viewModel = PostDetailConfigViewModel(
            preferencesService: PreferencesService(),
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )
        viewModel.selectSort(.Top)
        XCTAssertEqual(viewModel.currentSort, .Top)
        XCTAssertEqual(selected, .Top)
    }
}
