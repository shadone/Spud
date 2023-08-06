//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

class DependencyContainer: ObservableObject,
    HasDataStore,
    HasAccountService,
    HasSiteService,
    HasImageService,
    HasAlertService,
    HasEntryService
{
    static let shared = DependencyContainer()

    // MARK: Public

    let dataStore: DataStoreType = DataStore()
    let accountService: AccountServiceType
    let siteService: SiteServiceType
    let imageService: ImageServiceType
    let alertService: AlertServiceType = AlertService()
    let entryService: EntryServiceType

    // MARK: Functions

    init() {
        imageService = ImageService(alertService: alertService)
        siteService = SiteService(dataStore: dataStore)
        accountService = AccountService(
            siteService: siteService,
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
        siteService.startService()
        entryService.startService()
    }
}
