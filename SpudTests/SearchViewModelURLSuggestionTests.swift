//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import XCTest
@testable import Spud

@MainActor
final class SearchViewModelURLSuggestionTests: XCTestCase {
    private func makeViewModel(
        isKnownInstance: @escaping (String) -> Bool = { _ in false }
    ) throws -> SearchViewModel {
        let appDatabase = try AppDatabase.inMemory()
        let accountService = AccountService(appDatabase: appDatabase)
        let scope = accountService.scope(forAccountKeychainId: "test")
        return SearchViewModel(
            accountScope: scope,
            alertService: AlertService(),
            isKnownInstance: isKnownInstance
        )
    }

    func test_urlQuery_setsSuggestion_andDoesNotSearch() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        XCTAssertNotNil(viewModel.urlSuggestion)
        XCTAssertEqual(viewModel.urlSuggestion?.kind, .post)
        // No search was scheduled: phase stays .initial (scheduleSearch sets .loading).
        XCTAssertEqual(viewModel.phase, .initial)
    }

    func test_plainTextQuery_clearsSuggestion_andSearches() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        XCTAssertNotNil(viewModel.urlSuggestion)

        viewModel.queryChanged("cats")
        XCTAssertNil(viewModel.urlSuggestion)
        // A search was scheduled: scheduleSearch sets phase to .loading synchronously.
        XCTAssertEqual(viewModel.phase, .loading)
    }

    func test_emptyQuery_clearsSuggestion() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        viewModel.queryChanged("")
        XCTAssertNil(viewModel.urlSuggestion)
        XCTAssertEqual(viewModel.phase, .initial)
    }
}
