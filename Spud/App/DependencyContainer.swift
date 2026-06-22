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
    HasPreferencesService,
    HasUnreadCountService,
    HasExplorerService,
    HasReachabilityMonitor
{
    let appDatabase: AppDatabase
    let siteService: SiteServiceType
    let accountService: AccountServiceType
    let imageService: ImageServiceType
    let schedulerService: SchedulerServiceType
    let postContentDetectorService: PostContentDetectorServiceType
    let appearanceService: AppearanceServiceType
    let appService: AppServiceType
    let alertService: AlertServiceType = AlertService()
    let preferencesService: PreferencesServiceType = PreferencesService()
    let unreadCountService: UnreadCountServiceType
    let explorerService: ExplorerServiceType
    let reachabilityMonitor: ReachabilityMonitoring

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
        appearanceService = AppearanceService(preferencesService: preferencesService)
        appService = AppService(preferencesService: preferencesService, appDatabase: appDatabase)
        unreadCountService = UnreadCountService(accountService: accountService)
        explorerService = ExplorerService(appDatabase: appDatabase)
        reachabilityMonitor = ReachabilityMonitor()
    }

    func start() {
        siteService.startService()
        schedulerService.startService()
        explorerService.startService(
            autoRefresh: preferencesService.explorerAutoRefreshEnabled,
            maxAge: preferencesService.explorerRefreshInterval.timeInterval
        )
    }
}
