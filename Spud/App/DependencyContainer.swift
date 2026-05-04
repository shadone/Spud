//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

@MainActor
struct DependencyContainer:
    HasVoid,
    HasAppDatabase,
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
    let appDatabase: AppDatabase
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

    init(arguments: [AppLaunchArgument]) {
        if arguments.contains(.staticImageService) {
            imageService = StaticImageService()
        } else {
            imageService = ImageService(alertService: alertService)
        }

        do {
            appDatabase = try AppDatabase()
        } catch {
            fatalError("Failed to open AppDatabase: \(error)")
        }

        siteService = SiteService(appDatabase: appDatabase)
        accountService = AccountService(appDatabase: appDatabase)
        schedulerService = SchedulerService(
            appDatabase: appDatabase,
            accountService: accountService,
            alertService: alertService
        )
        postContentDetectorService = PostContentDetectorService()
        appService = AppService(preferencesService: preferencesService, appDatabase: appDatabase)
    }

    func start() {
        siteService.startService()
        schedulerService.startService()
    }
}
