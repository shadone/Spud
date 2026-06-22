//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class PostDetailViewModelLoadingTests: XCTestCase {
    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType

        init() {
            let appDatabase = try! AppDatabase.inMemory()
            accountService = AccountService(appDatabase: appDatabase)
            alertService = AlertService()
            preferencesService = PreferencesService()
        }
    }

    private func makeViewModel() -> PostDetailViewModel {
        let dependencies = TestDependencies()
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            dependencies: dependencies
        )
    }

    func testIsLoadingCommentsDefaultsFalse() {
        XCTAssertFalse(makeViewModel().isLoadingComments)
    }
}
