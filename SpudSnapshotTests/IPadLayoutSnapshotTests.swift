//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUtilKit
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// iPad-landscape snapshot of Discover: verifies the rails render as an adaptive
/// grid (not a horizontal carousel) and the directory column is capped rather than
/// stretching full-bleed across the wide canvas.
///
/// Uses `.image(on: .iPadPro11(.landscape), traits:)` which pins an explicit
/// device size, so any simulator works — no need to run on a specific device or
/// runtime for these refs.
@MainActor
final class IPadLayoutSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))

    @MainActor
    private struct SnapshotDependencies: HasAccountService, HasAlertService, HasAppDatabase, HasPreferencesService {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let appDatabase: AppDatabase
        let preferencesService: PreferencesServiceType
    }

    func test_discover_populated_ipad_landscape() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedDiscoverCommunities(into: appDatabase)

        let dependencies = SnapshotDependencies(
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            appDatabase: appDatabase,
            preferencesService: PreferencesService()
        )
        let viewModel = DiscoverViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "snapshot-signed-out"),
            isSignedIn: false,
            dependencies: dependencies,
            onOpenCommunity: { _ in },
            onOpenPack: { _ in },
            onOpenInstance: { _ in },
            onSeeAllCommunities: { _, _ in },
            onSeeAllInstances: { _, _ in },
            onRequestSignIn: { }
        )

        // The rails arrive via an async observation; wait for them.
        try await waitUntil {
            !viewModel.isLoading && viewModel.trending.count > DiscoverViewModel.railCarouselCount
        }

        let view = DiscoverView(viewModel: viewModel, accent: teal)
            .environment(\.imageService, StaticImageService())
        let host = UIHostingController(rootView: view)

        assertSnapshot(
            matching: host,
            as: .image(
                on: .iPadPro11(.landscape),
                traits: UITraitCollection(userInterfaceStyle: .light)
            ),
            named: "light"
        )
    }

    // MARK: - Profile banner iPad snapshot

    /// Verifies that the profile banner is centred within a capped column on iPad
    /// (regular size class) and does not render as a full-width filmstrip.
    ///
    /// Uses nil image URLs so the view renders the deterministic placeholder
    /// synchronously — no async settling needed.
    func test_profileBanner_ipad_landscape_light() {
        let view = makeProfileBannerFixture()
        let host = UIHostingController(rootView: AnyView(view))
        host.view.frame = CGRect(
            origin: .zero,
            size: ViewImageConfig.iPadPro11(.landscape).size ?? CGSize(width: 1194, height: 834)
        )
        host.view.layoutIfNeeded()
        assertSnapshot(
            matching: host,
            as: .image(
                on: .iPadPro11(.landscape),
                traits: UITraitCollection(userInterfaceStyle: .light)
            ),
            named: "light"
        )
    }

    // MARK: - Profile banner helpers

    /// Builds a display-only `ProfileBannerHeaderView` with nil URLs (placeholder)
    /// suitable for a synchronous snapshot — mirrors `ProfileBannerSnapshotTests.makeBannerView`.
    private func makeProfileBannerFixture() -> some View {
        ProfileBannerHeaderView(
            bannerUrl: nil,
            avatarUrl: nil,
            name: "testuser",
            isUploadingBanner: false,
            isUploadingAvatar: false,
            onPickBanner: nil,
            onPickAvatar: nil,
            onRemoveBanner: nil,
            onRemoveAvatar: nil
        )
        .environment(\.imageService, StaticImageService())
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Community reading split snapshot

    /// A flat dependency bag satisfying the full `CommunityReadingSplitViewController.Dependencies`
    /// protocol composition. All nested `Has*` protocols ultimately expand to the union below;
    /// spelling it out avoids a recursive typealias cycle (PostList → PostDetail → Community →
    /// PostList) and keeps the test self-contained.
    @MainActor
    private struct CommunitySplitDependencies:
        HasAccountService, HasAlertService, HasAppDatabase, HasAppService,
        HasAppearanceService, HasDiagnosticLog, HasImageService, HasLinkEmbedService,
        HasPostContentDetectorService, HasPreferencesService, HasReachabilityMonitor, HasVoid
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let appDatabase: AppDatabase
        let appService: AppServiceType
        let appearanceService: AppearanceServiceType
        let diagnosticLog: DiagnosticLogging
        let imageService: ImageServiceType
        let linkEmbedService: LinkEmbedServiceType
        let postContentDetectorService: PostContentDetectorServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring
    }

    /// iPad-landscape snapshot of `CommunityReadingSplitViewController`: verifies the
    /// two-column layout — primary column and secondary "No posts selected" placeholder —
    /// in its settled post-error state (the `fetchCommunityInfo` Task has completed
    /// and the loading indicator has stopped).
    ///
    /// A minimal signed-out account is seeded so `AccountService.lemmyService()` can
    /// create a `LemmyService` without a fatalError. The fetch to `example.com` fails
    /// immediately (not a Lemmy endpoint), the indicator stops, and the snapshot captures
    /// the empty-but-settled layout. The key assertion is structural: the split VC shows
    /// two columns and the secondary column contains the "No posts selected" placeholder.
    ///
    /// Uses `drawHierarchyInKeyWindow: true` (rendered on-screen via a real `UIWindow`)
    /// so the settled VC state is captured rather than a fresh re-render. This is the
    /// same strategy used for `UIVisualEffectView` blur snapshots (see CLAUDE.md).
    func test_communitySplit_emptyDetail_ipad_landscape() async throws {
        let appDatabase = try AppDatabase.inMemory()
        // Seed a minimal signed-out account so AccountService.lemmyService(forAccountKeychainId:)
        // can resolve the account row without fatalError-ing on a missing record.
        try await seedTestAccount(into: appDatabase, keychainId: "snapshot")

        let preferencesService = PreferencesService()
        let reachabilityMonitor = StaticReachabilityMonitor(isOnline: true)
        let appService = AppService(
            preferencesService: preferencesService,
            appDatabase: appDatabase,
            reachabilityMonitor: reachabilityMonitor,
            webArchiveStore: nil
        )
        let dependencies = CommunitySplitDependencies(
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            appDatabase: appDatabase,
            appService: appService,
            appearanceService: AppearanceService(preferencesService: preferencesService),
            diagnosticLog: DiagnosticLog(appDatabase: appDatabase),
            imageService: StaticImageService(),
            linkEmbedService: LinkEmbedService(),
            postContentDetectorService: PostContentDetectorService(),
            preferencesService: preferencesService,
            reachabilityMonitor: reachabilityMonitor
        )
        let instance = try XCTUnwrap(InstanceActorId(from: "https://example.com"))
        let splitVC = CommunityReadingSplitViewController(
            communityName: "programming",
            instance: instance,
            accountKeychainId: "snapshot",
            dependencies: dependencies
        )

        // Place the split VC on a visible UIWindow so all nested VCs (the embedded
        // UISplitViewController, primaryNav, CommunityOrLoadingViewController) receive
        // viewDidLoad and their async Tasks fire. Without an on-screen window the
        // UINavigationController never loads its root VC's view and the loading
        // indicator Task never starts — the snapshot would always capture mid-loading.
        let size = ViewImageConfig.iPadPro11(.landscape).size ?? CGSize(width: 1194, height: 834)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = splitVC
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        // Wait for the primary column's loading indicator to stop. The network fetch to
        // example.com fails immediately (not a Lemmy endpoint) and
        // CommunityOrLoadingViewController stops the indicator in its catch block.
        let deadline = Date().addingTimeInterval(10)
        while hasAnimatingIndicator(in: splitVC.view) {
            if Date() > deadline {
                XCTFail("Loading indicator never stopped — fetchCommunityInfo appears to be hanging")
                window.rootViewController = nil
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        // Snapshot the settled on-screen hierarchy. drawHierarchyInKeyWindow: true
        // captures the live view state rather than doing a fresh offscreen re-render
        // (which would replay viewDidLoad and show the spinner again).
        window.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        assertSnapshot(
            matching: splitVC,
            as: .image(drawHierarchyInKeyWindow: true, size: size, traits: UITraitCollection(userInterfaceStyle: .light)),
            named: "light"
        )

        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        assertSnapshot(
            matching: splitVC,
            as: .image(drawHierarchyInKeyWindow: true, size: size, traits: UITraitCollection(userInterfaceStyle: .dark)),
            named: "dark"
        )

        window.rootViewController = nil
    }

    // MARK: - Community split helpers

    /// Seed a minimal signed-out account row so `AccountService.lemmyService(forAccountKeychainId:)`
    /// can resolve the account without hitting its `fatalError("No account registered…")`.
    ///
    /// Inserts InstanceRecord → SiteRecord → AccountRecord in a single GRDB write transaction,
    /// following the same pattern used in `LemmyServiceSaveTests`.
    private func seedTestAccount(into appDatabase: AppDatabase, keychainId: String) async throws {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: true
            )
            try account.insert(db)
        }
    }

    /// Returns `true` if `view` or any of its descendants is an animating
    /// `UIActivityIndicatorView`. Used to poll for the end of the community-load
    /// network request in `test_communitySplit_emptyDetail_ipad_landscape`.
    private func hasAnimatingIndicator(in view: UIView) -> Bool {
        if let indicator = view as? UIActivityIndicatorView {
            return indicator.isAnimating
        }
        return view.subviews.contains { hasAnimatingIndicator(in: $0) }
    }

    // MARK: - Discover helpers

    /// Poll on the main actor until `condition` holds, failing loudly if it never does.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Discover landing did not populate within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Seed a deterministic set of Explorer communities across four hosts —
    /// mirrors the fixture in `DiscoverScreenSnapshotTests`.
    private func seedDiscoverCommunities(into appDatabase: AppDatabase) async throws {
        let hosts = ["lemmy.world", "beehaw.org", "lemmy.ml", "sh.itjust.works"]
        let topics = [
            "Technology", "Gaming", "Science", "News", "Movies", "Music",
            "Books", "Art", "Food", "Travel", "Fitness", "Photography",
            "Programming", "Privacy", "Space", "History", "Nature", "Pets",
            "Cars", "Finance", "DIY", "Comics", "Sports", "Memes",
        ]
        try await appDatabase.writer.write { db in
            for (index, topic) in topics.enumerated() {
                let host = hosts[index % hosts.count]
                let name = topic.lowercased()
                let weight = Int64(topics.count - index)
                var record = ExplorerCommunityRecord(
                    url: "https://\(host)/c/\(name)",
                    baseurl: host,
                    name: name,
                    title: topic,
                    isNsfw: false,
                    numberOfSubscribers: weight * 1000,
                    numberOfPosts: weight * 200,
                    numberOfComments: weight * 800,
                    usersActiveDay: weight * 30,
                    usersActiveWeek: weight * 150,
                    usersActiveMonth: weight * 400,
                    usersActiveHalfYear: weight * 900,
                    score: Double(weight) / Double(topics.count),
                    isSuspicious: false
                )
                try record.insert(db)
            }
        }
    }
}
