//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import CoreData
import SpudDataKit

class DependencyContainer: ObservableObject,
    HasDataStore,
    HasAccountService,
    HasAlertService,
    HasEntryService
{
    static let shared = DependencyContainer()

    // MARK: Public

    let dataStore: DataStoreType = DataStore()
    let accountService: AccountServiceType
    let alertService: AlertServiceType = AlertService()
    let entryService: EntryServiceType

    // MARK: Functions

    init() {
        accountService = AccountService(
            siteService: EmptySiteService(),
            dataStore: dataStore
        )
        entryService = EntryService(
            dataStore: dataStore,
            accountService: accountService
        )

        start()
    }

    private func start() {
        dataStore.startService()
        entryService.startService()
    }
}

private class EmptySiteService: SiteServiceType {
    func startService() { }

    func allSites(in context: NSManagedObjectContext) -> [LemmySite] {
        fatalError()
    }

    func populateSiteListWithSuggestedInstancesIfNeeded() { }

    func site(for instance: String, in context: NSManagedObjectContext) -> LemmySite {
        fatalError()
    }
}
