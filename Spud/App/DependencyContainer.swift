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
    HasNodeInfoService,
    HasImageService,
    HasLinkEmbedService,
    HasSchedulerService,
    HasPostContentDetectorService,
    HasAppearanceService,
    HasAppService,
    HasAlertService,
    HasPreferencesService,
    HasUnreadCountService,
    HasExplorerService,
    HasReachabilityMonitor,
    HasDiagnosticLog
{
    let appDatabase: AppDatabase
    let siteService: SiteServiceType
    let accountService: AccountServiceType
    let nodeInfoService: NodeInfoServiceType
    let imageService: ImageServiceType
    let linkEmbedService: LinkEmbedServiceType
    let schedulerService: SchedulerServiceType
    let postContentDetectorService: PostContentDetectorServiceType
    let appearanceService: AppearanceServiceType
    let appService: AppServiceType
    let alertService: AlertServiceType = AlertService()
    let preferencesService: PreferencesServiceType = PreferencesService()
    let unreadCountService: UnreadCountServiceType
    let explorerService: ExplorerServiceType
    let reachabilityMonitor: ReachabilityMonitoring
    let diagnosticLog: DiagnosticLogging

    // MARK: Functions

    init(arguments: [AppLaunchArgument]) {
        if arguments.contains(.staticImageService) {
            imageService = StaticImageService()
        } else {
            imageService = ImageService(alertService: alertService)
        }
        linkEmbedService = LinkEmbedService()

        // Reuse the process-wide singleton rather than opening a SECOND
        // DatabasePool. `AppDelegate`'s launch-time prune tasks touch
        // `AppDatabase.shared`, so creating a distinct instance here meant two
        // connections ran the GRDB migrator against the same file at first
        // launch. They raced on `BEGIN IMMEDIATE` (SQLITE_BUSY) and — once a busy
        // timeout serialized that — the second connection re-applied migrations
        // the first had already run ("table already exists"), because the
        // migrator is not safe to run concurrently from two connections. The
        // singleton's `static let` guarantees exactly one thread-safe init, so the
        // migrator runs once no matter whether the prune task or the DI graph
        // touches the database first. (`AppDatabase.shared` fatalErrors on a
        // genuine open failure, preserving the previous crash-on-unavailable-DB
        // behavior.)
        appDatabase = .shared

        diagnosticLog = DiagnosticLog(appDatabase: appDatabase)
        reachabilityMonitor = ReachabilityMonitor()
        siteService = SiteService(appDatabase: appDatabase)
        nodeInfoService = NodeInfoService(fetcher: LiveNodeInfoFetcher(), appDatabase: appDatabase)
        accountService = AccountService(
            appDatabase: appDatabase,
            reachabilityMonitor: reachabilityMonitor,
            nodeInfoService: nodeInfoService
        )
        schedulerService = SchedulerService(
            appDatabase: appDatabase,
            accountService: accountService,
            alertService: alertService,
            diagnostics: diagnosticLog,
            reachabilityMonitor: reachabilityMonitor
        )
        postContentDetectorService = PostContentDetectorService()
        appearanceService = AppearanceService(preferencesService: preferencesService)
        appService = AppService(
            preferencesService: preferencesService,
            appDatabase: appDatabase,
            reachabilityMonitor: reachabilityMonitor,
            // try? — a missing App Group container disables offline reading
            // (links fall back to Safari/browser); it is never fatal here.
            webArchiveStore: try? OfflineWebArchiveStore(appDatabase: appDatabase)
        )
        unreadCountService = UnreadCountService(accountService: accountService, diagnostics: diagnosticLog)
        explorerService = ExplorerService(appDatabase: appDatabase)
    }

    func start() {
        // Bound the diagnostic log table at launch so it doesn't grow unboundedly.
        Task { try? await appDatabase.pruneDiagnosticEvents(now: Date().timeIntervalSince1970) }
        siteService.startService()
        schedulerService.startService()
        explorerService.startService(
            autoRefresh: preferencesService.explorerAutoRefreshEnabled,
            maxAge: preferencesService.explorerRefreshInterval.timeInterval
        )
    }
}
