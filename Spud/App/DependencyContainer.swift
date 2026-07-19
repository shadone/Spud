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
    HasMetaCommunityService,
    HasStatsService
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
    let statsService: StatsServicing

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
        statsService = StatsService(appDatabase: appDatabase)

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
        // A plain local `let` (no `nonisolated(unsafe)` needed - `showNsfwProvider`'s
        // seam type is itself `@MainActor`, so it may read `preferencesService`
        // directly). Still required to go through a local rather than closing
        // over `self.preferencesService` inline below: `DependencyContainer` is a
        // struct, and an escaping closure built in `init` can't capture `self`
        // before every stored property is initialized.
        let preferencesServiceForScheduler = preferencesService
        schedulerService = SchedulerService(
            appDatabase: appDatabase,
            accountService: accountService,
            alertService: alertService,
            diagnostics: diagnosticLog,
            reachabilityMonitor: reachabilityMonitor,
            // Wires the real user preference through to the scheduler's
            // community-follow poll (see `SchedulerService.showNsfwProvider`'s
            // doc comment).
            showNsfwProvider: { preferencesServiceForScheduler.showNsfw }
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

        // Fun stats: install the global recording facade and keep the
        // service's enabled flag bound to the preference. Skipped under
        // XCTest so hosted unit tests never record into the shared DB.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            FunStats.install(statsService)
            let statsService = statsService
            let preferencesService = preferencesService
            Task {
                for await isEnabled in preferencesService.funStatsCollectionEnabledStream {
                    await statsService.setEnabled(isEnabled)
                }
            }
        } else {
            // `SceneDelegate` calls `statsService.appDidBecomeActive()` /
            // `appWillResignActive()` directly (not through the `FunStats`
            // facade, which IS gated by leaving it uninstalled above) because
            // it needs the concrete `StatsServicing` reference from
            // `dependencies`, not the fire-and-forget facade. That bypasses
            // the facade's XCTest gate, so app-hosted test runs (SpudTests,
            // SpudUITests) would otherwise still buffer sessionCount /
            // foregroundSeconds via those lifecycle calls and flush them into
            // the shared simulator DB. Explicitly disabling the service here
            // closes that hole without touching `SceneDelegate`.
            let statsService = statsService
            Task { await statsService.setEnabled(false) }
        }
    }
}
