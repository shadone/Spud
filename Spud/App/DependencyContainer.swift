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
    HasImageService,
    HasSchedulerService,
    HasPostContentDetectorService,
    HasAppearanceService
{
    let dataStore: DataStoreType = DataStore()
    let siteService: SiteServiceType
    let accountService: AccountServiceType
    let imageService: ImageServiceType = ImageService()
    let schedulerService: SchedulerServiceType
    let postContentDetectorService: PostContentDetectorServiceType
    let appearanceService: AppearanceServiceType = AppearanceService()

    // MARK: Functions

    init() {
        siteService = SiteService(dataStore: dataStore)
        accountService = AccountService(dataStore: dataStore)
        schedulerService = SchedulerService(
            dataStore: dataStore,
            accountService: accountService,
            siteService: siteService
        )
        postContentDetectorService = PostContentDetectorService()

        start()
    }

    private func start() {
        dataStore.startService()
        schedulerService.startService()
    }
}
