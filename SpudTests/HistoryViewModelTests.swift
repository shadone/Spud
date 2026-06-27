//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

@MainActor
struct HistoryViewModelTests {
    @Test
    func defaultsToReadModeAndEmptySearch() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        #expect(vm.mode == .read)
        #expect(vm.searchQuery == nil)
    }

    @Test
    func searchTextNormalizesToNilWhenBlank() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        vm.searchText = "  "
        #expect(vm.searchQuery == nil)
        vm.searchText = "  swift "
        #expect(vm.searchQuery == "swift")
    }

    @Test
    func modeIsMutable() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        vm.mode = .saved
        #expect(vm.mode == .saved)
    }
}
