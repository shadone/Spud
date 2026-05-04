//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit

class DependencyContainer: ObservableObject,
    HasAppDatabase,
    HasAccountService,
    HasAlertService,
    HasEntryService
{
    static let shared = DependencyContainer()

    // MARK: Public

    let appDatabase: AppDatabase
    let accountService: AccountServiceType
    let alertService: AlertServiceType = AlertService()
    let entryService: EntryServiceType

    // MARK: Functions

    init() {
        do {
            appDatabase = try AppDatabase()
        } catch {
            fatalError("Failed to open AppDatabase: \(error)")
        }

        accountService = AccountService(appDatabase: appDatabase)
        entryService = EntryService(
            appDatabase: appDatabase,
            accountService: accountService
        )

        start()
    }

    private func start() {
        entryService.startService()
    }
}
