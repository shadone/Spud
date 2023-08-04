//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct DependencyContainer:
    HasVoid,
    HasDataStore,
    HasSiteService,
    HasAccountService,
    HasImageService,
    HasSchedulerService,
    HasPostContentDetectorService,
    HasAppearanceService,
    HasAppService,
    HasAlertService,
    HasPreferencesService
{
    let dataStore: DataStoreType = DataStore()
    let siteService: SiteServiceType
    let accountService: AccountServiceType
    let imageService: ImageServiceType
    let schedulerService: SchedulerServiceType
    let postContentDetectorService: PostContentDetectorServiceType
    let appearanceService: AppearanceServiceType = AppearanceService()
    let appService: AppServiceType
    let alertService: AlertServiceType = AlertService()
    let preferencesService: PreferencesServiceType = PreferencesService()

    // MARK: Functions

    init() {
        imageService = ImageService(alertService: alertService)
        siteService = SiteService(dataStore: dataStore)
        accountService = AccountService(
            siteService: siteService,
            dataStore: dataStore
        )
        schedulerService = SchedulerService(
            dataStore: dataStore,
            accountService: accountService,
            siteService: siteService,
            alertService: alertService
        )
        postContentDetectorService = PostContentDetectorService()
        appService = AppService(preferencesService: preferencesService)
    }

    func start() {
        dataStore.startService()
        schedulerService.startService()
        siteService.startService()
    }
}
