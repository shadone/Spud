//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
import UIKit
@testable import Spud

// MARK: - Test doubles

/// Minimal `ImageServiceType` stub — `fetch(_:thumbnail:)` never yields so no
/// async image loading happens while a `CommunityReadingSplitViewController` is
/// constructed in the test.
private final class NullImageService: ImageServiceType, @unchecked Sendable {
    func fetch(_: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
        AsyncStream { $0.finish() }
    }
}

/// A fake dependency container conforming to the full app dependency surface
/// (mirrors the production `DependencyContainer` but with an in-memory database
/// and a no-op image service). `CommunityReadingSplitViewController`'s
/// `Dependencies` composition flattens — via the nested post-detail / person /
/// instance screens — to nearly the entire graph, so providing the superset is
/// the robust way to satisfy it without hand-tracing the recursion. Internal (not
/// file-private) so sibling suites — e.g.
/// `ActivitySummaryReadingSplitViewControllerTests` — reuse the same superset
/// harness.
private struct StubNodeInfoService: NodeInfoServiceType {
    func detect(host _: String, maxAge _: TimeInterval) async -> NodeInfoDetection {
        .unknown
    }
}

@MainActor
struct FakeDependencies:
    HasVoid,
    HasAppDatabase,
    HasSiteService,
    HasAccountService,
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
    HasNodeInfoService
{
    let appDatabase: AppDatabase
    let siteService: SiteServiceType
    let accountService: AccountServiceType
    let imageService: ImageServiceType
    let linkEmbedService: LinkEmbedServiceType
    let schedulerService: SchedulerServiceType
    let postContentDetectorService: PostContentDetectorServiceType
    let appearanceService: AppearanceServiceType
    let appService: AppServiceType
    let alertService: AlertServiceType
    let preferencesService: PreferencesServiceType
    let unreadCountService: UnreadCountServiceType
    let explorerService: ExplorerServiceType
    let reachabilityMonitor: ReachabilityMonitoring
    let diagnosticLog: DiagnosticLogging
    let nodeInfoService: NodeInfoServiceType

    init() {
        let appDatabase = try! AppDatabase.inMemory()
        self.appDatabase = appDatabase
        let reachabilityMonitor = StaticReachabilityMonitor(isOnline: true)
        self.reachabilityMonitor = reachabilityMonitor
        let preferencesService = PreferencesService()
        self.preferencesService = preferencesService
        let alertService = AlertService()
        self.alertService = alertService
        let diagnosticLog = DiagnosticLog(appDatabase: appDatabase)
        self.diagnosticLog = diagnosticLog
        let accountService = AccountService(appDatabase: appDatabase, reachabilityMonitor: reachabilityMonitor)
        self.accountService = accountService

        imageService = NullImageService()
        linkEmbedService = LinkEmbedService()
        siteService = SiteService(appDatabase: appDatabase)
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
            webArchiveStore: nil
        )
        unreadCountService = UnreadCountService(accountService: accountService, diagnostics: diagnosticLog)
        explorerService = ExplorerService(appDatabase: appDatabase)
        nodeInfoService = StubNodeInfoService()
    }
}

// MARK: - Tests

/// Verifies `SplitTabResolver` classifies the currently selected tab into the
/// right `DetailRouteTarget` so the detail router lands a pushed post in the
/// active reading context's secondary column instead of hijacking the Posts tab.
@MainActor
struct SplitTabResolverTests {
    @Test
    func resolvesPostsSplitWhenSelected() {
        let posts = UISplitViewController(style: .doubleColumn)
        let target = SplitTabResolver.target(for: posts, postsSplit: posts)
        guard case .postsSplit = target else {
            Issue.record("expected .postsSplit, got \(target)")
            return
        }
    }

    @Test
    func resolvesCommunityReadingSplitOnTopOfNavStack() throws {
        let posts = UISplitViewController(style: .doubleColumn)
        let community = try CommunityReadingSplitViewController(
            communityName: "test",
            instance: #require(InstanceActorId(from: "https://example.com")),
            accountKeychainId: "kc-test",
            dependencies: FakeDependencies()
        )
        let nav = UINavigationController(rootViewController: UIViewController())
        nav.pushViewController(community, animated: false)

        let target = SplitTabResolver.target(for: nav, postsSplit: posts)
        guard case let .community(resolved) = target else {
            Issue.record("expected .community, got \(target)")
            return
        }
        #expect(resolved === community)
    }

    @Test
    func resolvesActivitySummarySplitOnTopOfNavStack() throws {
        let posts = UISplitViewController(style: .doubleColumn)
        let dependencies = FakeDependencies()
        // `ActivityViewController.init` (built inside the container) eagerly
        // resolves the account's `lemmyService` scope, which fatal-errors for an
        // unregistered keychain id, so register a signed-out account first.
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = dependencies.accountService.accountForSignedOut(
            forInstance: instance,
            isServiceAccount: false
        )
        let split = ActivitySummaryReadingSplitViewController(
            accountKeychainId: keychainId,
            initialFilters: [.post, .comment, .save],
            dependencies: dependencies
        )
        let nav = UINavigationController(rootViewController: UIViewController())
        nav.pushViewController(split, animated: false)

        let target = SplitTabResolver.target(for: nav, postsSplit: posts)
        guard case let .activitySummary(resolved) = target else {
            Issue.record("expected .activitySummary, got \(target)")
            return
        }
        #expect(resolved === split)
    }

    @Test
    func resolvesPlainNavWhenTopIsOrdinaryViewController() {
        let posts = UISplitViewController(style: .doubleColumn)
        let nav = UINavigationController(rootViewController: UIViewController())

        let target = SplitTabResolver.target(for: nav, postsSplit: posts)
        guard case let .plainNav(resolved) = target else {
            Issue.record("expected .plainNav, got \(target)")
            return
        }
        #expect(resolved === nav)
    }

    @Test
    func resolvesNoneWhenSelectionIsNil() {
        let posts = UISplitViewController(style: .doubleColumn)
        let target = SplitTabResolver.target(for: nil, postsSplit: posts)
        guard case .none = target else {
            Issue.record("expected .none, got \(target)")
            return
        }
    }
}
