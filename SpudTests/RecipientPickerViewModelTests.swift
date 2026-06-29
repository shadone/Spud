//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
@testable import Spud

@MainActor
struct RecipientPickerViewModelTests {
    // MARK: Helpers

    private func makeUser(id: Int32, name: String) -> SearchUserResult {
        SearchUserResult(
            serverPersonId: id,
            name: name,
            qualifiedName: "@\(name)@example.com",
            instance: InstanceActorId(from: "example.com")!,
            avatarUrl: nil
        )
    }

    /// Polls until `condition` holds or the budget is exhausted. The view model's
    /// search runs on a Task; the immediate `submit()` path still hops the runloop
    /// once before `performSearch` settles the phase.
    private func settle(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Tests

    @Test
    func startsInInitialPhaseWithNoResults() {
        let viewModel = RecipientPickerViewModel(searchUsers: { _ in [] })
        #expect(viewModel.phase == .initial)
        #expect(viewModel.results.isEmpty)
    }

    @Test
    func emptyQuery_doesNotSearch_staysInitial() async {
        var searchCount = 0
        let viewModel = RecipientPickerViewModel(searchUsers: { _ in
            searchCount += 1
            return []
        })
        viewModel.queryChanged("   ")
        // Give any (erroneously) scheduled task a chance to run.
        await settle { false }
        #expect(viewModel.phase == .initial)
        #expect(searchCount == 0)
    }

    @Test
    func nonEmptyQuery_entersLoadingSynchronously() {
        let viewModel = RecipientPickerViewModel(searchUsers: { _ in [] })
        viewModel.queryChanged("alice")
        // scheduleSearch sets .loading synchronously, before the debounce elapses.
        #expect(viewModel.phase == .loading)
    }

    @Test
    func submit_mapsResults_andLoads() async {
        let viewModel = RecipientPickerViewModel(searchUsers: { query in
            #expect(query == "alice")
            return [makeUser(id: 1, name: "alice")]
        })
        viewModel.queryChanged("alice")
        // submit() runs immediately (no debounce) so the test doesn't wait 300ms.
        viewModel.submit()

        await settle { viewModel.phase == .loaded }

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.results.map(\.name) == ["alice"])
        #expect(viewModel.lastSearchedQuery == "alice")
    }

    @Test
    func submit_emptyResults_loadsWithNoResults() async {
        let viewModel = RecipientPickerViewModel(searchUsers: { _ in [] })
        viewModel.queryChanged("nobody")
        viewModel.submit()

        await settle { viewModel.phase == .loaded }

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.lastSearchedQuery == "nobody")
    }

    @Test
    func submit_emptyQuery_doesNotSearch_resetsToInitial() async {
        var searchCount = 0
        let viewModel = RecipientPickerViewModel(searchUsers: { _ in
            searchCount += 1
            return [makeUser(id: 1, name: "alice")]
        })
        // First a real search so there's a non-initial phase + results to reset.
        viewModel.queryChanged("alice")
        viewModel.submit()
        await settle { viewModel.phase == .loaded }
        #expect(searchCount == 1)
        #expect(!viewModel.results.isEmpty)

        // Now a whitespace-only query: submit must NOT fire another search and
        // must reset to the initial prompt with no results (mirrors queryChanged).
        viewModel.queryChanged("   ")
        viewModel.submit()
        // Give any (erroneously) scheduled task a chance to run.
        await settle { false }
        #expect(viewModel.phase == .initial)
        #expect(viewModel.results.isEmpty)
        #expect(searchCount == 1)
    }

    @Test
    func searchFailure_entersErrorPhase() async {
        let viewModel = RecipientPickerViewModel(searchUsers: { _ in
            throw URLError(.notConnectedToInternet)
        })
        viewModel.queryChanged("alice")
        viewModel.submit()

        await settle { viewModel.phase == .error }

        #expect(viewModel.phase == .error)
        #expect(viewModel.results.isEmpty)
    }

    @Test
    func clearingQuery_resetsToInitial() async {
        let viewModel = RecipientPickerViewModel(searchUsers: { _ in
            [makeUser(id: 1, name: "alice")]
        })
        viewModel.queryChanged("alice")
        viewModel.submit()
        await settle { viewModel.phase == .loaded }
        #expect(!viewModel.results.isEmpty)

        viewModel.queryChanged("")
        #expect(viewModel.phase == .initial)
        #expect(viewModel.results.isEmpty)
    }
}
