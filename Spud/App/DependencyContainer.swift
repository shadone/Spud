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
    HasDiagnosticLog,
    HasMetaCommunityService
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
    let metaCommunityService: MetaCommunityServiceType

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
        // `nonisolated(unsafe)`: `ReminderService` (a `SpudDataKit` actor) reads
        // this closure synchronously off-main, so it can't capture the
        // `@MainActor`-isolated `preferencesService` directly - `reminderNotificationsEnabled`
        // itself is `nonisolated` (genuinely thread-safe; see that property's doc
        // comment), but `PreferencesServiceType` as a whole isn't `Sendable`, so
        // the compiler can't verify capturing the reference is safe on its own.
        // Trust is warranted here: only the one `nonisolated` property below is
        // ever touched through this capture.
        nonisolated(unsafe) let preferencesServiceForReminders = preferencesService
        accountService = AccountService(
            appDatabase: appDatabase,
            reachabilityMonitor: reachabilityMonitor,
            nodeInfoService: nodeInfoService,
            // Wires the real user preference through to `ReminderService`
            // (see that actor's `notificationsEnabled` doc comment) - without
            // this, every `ReminderService` defaults to always-enabled and
            // the in-app toggle is inert.
            reminderNotificationsEnabled: { preferencesServiceForReminders.reminderNotificationsEnabled }
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
        unreadCountService = UnreadCountService(accountService: accountService, appDatabase: appDatabase, diagnostics: diagnosticLog)
        explorerService = ExplorerService(appDatabase: appDatabase)
        metaCommunityService = MetaCommunityService(
            resolver: LiveMetaCommunityResolver(
                accountService: accountService, appDatabase: appDatabase
            ),
            appDatabase: appDatabase
        )
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
