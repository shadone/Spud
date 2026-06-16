//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testDefaultsToReadModeAndEmptySearch() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        XCTAssertEqual(vm.mode, .read)
        XCTAssertNil(vm.searchQuery)
    }

    func testSearchTextNormalizesToNilWhenBlank() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        vm.searchText = "  "
        XCTAssertNil(vm.searchQuery)
        vm.searchText = "  swift "
        XCTAssertEqual(vm.searchQuery, "swift")
    }

    func testModeIsMutable() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        vm.mode = .saved
        XCTAssertEqual(vm.mode, .saved)
    }
}
