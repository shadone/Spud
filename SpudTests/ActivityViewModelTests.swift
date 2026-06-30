//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

/// Tests for `ActivityViewModel`.
///
/// Each test creates a lightweight `ActivityCoordinator` backed by an in-memory
/// `AppDatabase` with no authored source. Only the ViewModel's synchronous state
/// mutations are exercised here; async stream behavior is coordinator-level.
@MainActor
struct ActivityViewModelTests {
    private func makeViewModel() throws -> ActivityViewModel {
        let db = try AppDatabase.inMemory()
        let coordinator = ActivityCoordinator(appDatabase: db, personRowId: nil, authoredSource: nil)
        return ActivityViewModel(coordinator: coordinator, accountId: 0)
    }

    @Test
    func activeFiltersStartsEmpty() throws {
        let vm = try makeViewModel()
        #expect(vm.activeFilters.isEmpty)
    }

    @Test
    func toggleFilterAddsFilter() throws {
        let vm = try makeViewModel()
        vm.toggleFilter(.post)
        #expect(vm.activeFilters.contains(.post))
    }

    @Test
    func toggleFilterOnActiveRemovesIt() throws {
        let vm = try makeViewModel()
        vm.toggleFilter(.comment)
        vm.toggleFilter(.comment)
        #expect(!vm.activeFilters.contains(.comment))
    }

    @Test
    func multipleFiltersCanBeActiveSimultaneously() throws {
        let vm = try makeViewModel()
        vm.toggleFilter(.post)
        vm.toggleFilter(.vote)
        #expect(vm.activeFilters.contains(.post))
        #expect(vm.activeFilters.contains(.vote))
        #expect(vm.activeFilters.count == 2)
    }

    @Test
    func resetFiltersClearsBothFiltersAndQuery() throws {
        let vm = try makeViewModel()
        vm.toggleFilter(.save)
        vm.searchQuery = "lemmy"
        vm.resetFilters()
        #expect(vm.activeFilters.isEmpty)
        #expect(vm.searchQuery.isEmpty)
    }

    @Test
    func searchQueryStartsEmpty() throws {
        let vm = try makeViewModel()
        #expect(vm.searchQuery.isEmpty)
    }

    @Test
    func loadStateStartsIdle() throws {
        let vm = try makeViewModel()
        #expect(vm.loadState == .idle)
    }
}
