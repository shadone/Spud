//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit
import Testing
@testable import Spud

@MainActor
struct SearchViewModelURLSuggestionTests {
    private func makeViewModel(
        isKnownInstance: @escaping (String) -> Bool = { _ in false },
        searchInstances: @escaping @Sendable (String) -> [SearchInstanceResult] = { _ in [] }
    ) throws -> SearchViewModel {
        let appDatabase = try AppDatabase.inMemory()
        let accountService = AccountService(appDatabase: appDatabase)
        let scope = accountService.scope(forAccountKeychainId: "test")
        return SearchViewModel(
            accountScope: scope,
            alertService: AlertService(),
            preferencesService: PreferencesService(),
            appDatabase: appDatabase,
            isKnownInstance: isKnownInstance,
            searchInstances: searchInstances
        )
    }

    @Test
    func urlQuery_setsSuggestion_andDoesNotSearch() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        #expect(viewModel.urlSuggestion != nil)
        #expect(viewModel.urlSuggestion?.kind == .post)
        // No search was scheduled: phase stays .initial (scheduleSearch sets .loading).
        #expect(viewModel.phase == .initial)
    }

    @Test
    func plainTextQuery_clearsSuggestion_andSearches() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        #expect(viewModel.urlSuggestion != nil)

        viewModel.queryChanged("cats")
        #expect(viewModel.urlSuggestion == nil)
        // A search was scheduled: scheduleSearch sets phase to .loading synchronously.
        #expect(viewModel.phase == .loading)
    }

    @Test
    func emptyQuery_clearsSuggestion() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        viewModel.queryChanged("")
        #expect(viewModel.urlSuggestion == nil)
        #expect(viewModel.phase == .initial)
    }

    @Test
    func submit_withURLQuery_doesNotSearch() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        viewModel.submit()
        #expect(viewModel.urlSuggestion != nil)
        // submit() must not call scheduleSearch; phase stays .initial.
        #expect(viewModel.phase == .initial)
    }

    @Test
    func scopeChanged_withURLQuery_doesNotSearch() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        viewModel.scopeChanged(.communities)
        // scopeChanged() must not call scheduleSearch when a URL suggestion is active.
        #expect(viewModel.phase == .initial)
    }

    @Test
    func instancesScope_usesClientSideSearch_notLemmyApi() async throws {
        let record = ExplorerInstanceRecord(
            baseurl: "programming.dev",
            name: "Programming.dev",
            usersTotal: 5000
        )
        let viewModel = try makeViewModel(searchInstances: { query in
            #expect(query == "prog")
            return [SearchInstanceResult(record: record)]
        })
        // No network: this must resolve via the injected client-side closure.
        viewModel.scope = .instances
        viewModel.queryChanged("prog")
        viewModel.submit()

        // The detached client-side query + main-actor apply settle on the next yields.
        for _ in 0..<50 where viewModel.phase != .loaded {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.results.instances.map(\.baseurl) == ["programming.dev"])
    }
}
