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

    init() {
        siteService = SiteService(dataStore: dataStore)
        accountService = AccountService(dataStore: dataStore)
        start()
    }

    private func start() {
        dataStore.startService()
    }
}
