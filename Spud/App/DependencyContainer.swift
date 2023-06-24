//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct DependencyContainer:
    HasDataStore,
    HasSiteService,
    HasAccountService,
    HasImageService
{
    let dataStore: DataStoreType = DataStore()
    let siteService: SiteServiceType
    let accountService: AccountServiceType
    let imageService: ImageServiceType = ImageService()
    let schedulerServer: SchedulerServiceType

    // MARK: Functions

    init() {
        siteService = SiteService(dataStore: dataStore)
        accountService = AccountService(dataStore: dataStore)
        schedulerServer = SchedulerService(
            dataStore: dataStore,
            accountService: accountService,
            siteService: siteService
        )

        start()
    }

    private func start() {
        dataStore.startService()
        schedulerServer.startService()
    }
}
