//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUIKit
import UIKit
import XCTest
@testable import Spud

/// iPad-landscape structural snapshot of `ActivitySummaryReadingSplitViewController`:
/// proves that at regular width the Activity area renders as **two columns** — the
/// activity timeline in the primary (left) column and the Summary dashboard in the
/// secondary (right) column — rather than the single-column push stack it collapses
/// to on iPhone / compact width.
///
/// ## Determinism strategy (non-negotiable)
///
/// This initiative was repeatedly bitten by wall-clock-nondeterministic snapshots,
/// so every date-driven value is pinned:
///
/// - A **fixed `asOf`** (`2025-03-24T00:00:00Z`, a Monday) is threaded to the
///   Summary column so the 18-week heatmap window *and* the "Joined … " relative
///   age string are identical on every run, whatever the wall clock says. The age
///   is genuinely pinned: `asOf` flows `SummaryViewModel → observeSummaryStats →
///   PersonFormatter.string(personCreatedDate:asOf:)`, so the string is measured
///   against `asOf` (2025-03-24), **not** `Date()`. With a seeded join date of
///   2020-09-13 it therefore reads a stable "Joined 5y" rather than a record-time
///   value that would drift as the wall clock advances. This matches
///   `SummarySnapshotTests`, whose seeding we reuse verbatim.
/// - The **timeline column is rendered network-free**: the seeded account is a
///   signed-out record (so `AccountService.lemmyService(…)` never touches the
///   keychain) and the initial filter is `.save` only. Because the coordinator
///   fires an authored (network) fetch *only* when `.post`/`.comment` is enabled
///   (see `ActivityCoordinator.beginStreaming`), a `.save`-only filter starts a
///   pure local stream with no network at all. With no local save events seeded
///   the timeline settles deterministically into its empty state — no spinner,
///   no wall-clock, no I/O.
///
/// So the **Summary column is populated** (identity strip + stat tiles + heatmap)
/// and the **timeline column is in its settled empty state**. Per the Phase-3 task
/// guidance, the load-bearing assertion is the *side-by-side two-column geometry*,
/// not a populated timeline (there is no deterministic controller-backed timeline
/// seeding harness, and building one was explicitly out of scope).
///
/// ## Rendering strategy
///
/// Mirrors `IPadLayoutSnapshotTests.test_communitySplit_emptyDetail_ipad_landscape`
/// (the sibling two-column iPad split): the container is hosted on a real on-screen
/// `UIWindow` at `.iPadPro11(.landscape)` size so every nested VC receives its
/// appearance callbacks and async observations fire, the embedded split's size
/// class is forced `.regular` so it deterministically **expands** (two columns)
/// regardless of the host simulator, and the settled on-screen hierarchy is
/// captured with `drawHierarchyInKeyWindow: true` (an offscreen re-render would
/// replay `viewDidLoad` and could recapture a transient state). Structural code
/// assertions walk the live hierarchy *before* the pixel diff so broken split
/// routing fails loudly in code, not silently in a snapshot.
///
/// ## Cross-suite determinism (the safe-area pin)
///
/// `drawHierarchyInKeyWindow: true` makes swift-snapshot-testing render into the
/// process's **current key window** (`getKeyWindow()`), which is the host window
/// this fixture makes key just before capturing. A *stock* `UIWindow` derives its
/// `safeAreaInsets` from whatever window-scene it happens to be attached to, and
/// that attachment state is perturbed by any snapshot suite that ran earlier in the
/// same test process (e.g. `SummarySnapshotTests`' host windows). The split's nav
/// bars and the timeline table's `adjustedContentInset` are laid out under that top
/// inset, so a differing ambient inset shifted the *entire* two-column content
/// vertically (~38 pt) between an isolated run and a run that followed another
/// suite — the recorded ref then matched only the process state it was recorded in.
/// To make the capture independent of ambient scene state, the host window is a
/// `FixedSafeAreaWindow` that pins `safeAreaInsets` to `.zero` (matching the
/// zero-safe-area the `drawHierarchyInKeyWindow` strategy already forces via its
/// off-screen draw), so first-layout and draw-layout agree and the render is
/// byte-identical whatever ran before it.
@MainActor
final class ActivityIPadSplitSnapshotTests: XCTestCase {
    // MARK: - Dependency bag

    /// A flat dependency bag satisfying the full
    /// `ActivitySummaryReadingSplitViewController.Dependencies` protocol
    /// composition (`ActivityViewController.Dependencies &
    /// SummaryViewController.Dependencies`). Those nested `Has*` protocols expand,
    /// via the embedded post-detail / person / community / instance screens, to the
    /// same union `IPadLayoutSnapshotTests.CommunitySplitDependencies` spells out;
    /// enumerating it here avoids a recursive typealias cycle and keeps the test
    /// self-contained.
    private struct StubNodeInfoService: NodeInfoServiceType {
        func detect(host _: String, maxAge _: TimeInterval) async -> NodeInfoDetection {
            .unknown
        }
    }

    private struct SplitDependencies:
        HasAccountService, HasAlertService, HasAppDatabase, HasAppService,
        HasAppearanceService, HasDiagnosticLog, HasImageService, HasLinkEmbedService,
        HasNodeInfoService, HasPostContentDetectorService, HasPreferencesService,
        HasReachabilityMonitor, HasVoid
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let appDatabase: AppDatabase
        let appService: AppServiceType
        let appearanceService: AppearanceServiceType
        let diagnosticLog: DiagnosticLogging
        let imageService: ImageServiceType
        let linkEmbedService: LinkEmbedServiceType
        let nodeInfoService: NodeInfoServiceType
        let postContentDetectorService: PostContentDetectorServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring
    }

    // MARK: - Constants

    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    /// Keychain id shared by the seeded account; both columns resolve their row ids
    /// from it exactly the way the container does in production.
    private let keychainId = "snapshot-activity-split"

    /// 2025-03-24T00:00:00Z (Monday) — anchors the Summary heatmap window and the
    /// "joined … ago" string, so no wall-clock value reaches the render. Same
    /// instant `SummarySnapshotTests` uses.
    private let fixedAsOf = Date(timeIntervalSince1970: 1_742_774_400)

    // MARK: - Test

    private let size = ViewImageConfig.iPadPro11(.landscape).size ?? CGSize(width: 1194, height: 834)

    func test_activitySplit_ipad_landscape_light() async throws {
        let restoreAnimations = SnapshotDeterminism.disableAnimationsForCapture()
        defer { restoreAnimations() }

        let (container, window) = try await makeSettledSplit(style: .light)
        defer { window.rootViewController = nil }

        assertTwoColumnStructure(container, window: window)
        assertSnapshot(
            matching: container,
            as: .image(
                drawHierarchyInKeyWindow: true,
                size: size,
                traits: UITraitCollection(userInterfaceStyle: .light)
            ),
            named: "light"
        )
    }

    func test_activitySplit_ipad_landscape_dark() async throws {
        let restoreAnimations = SnapshotDeterminism.disableAnimationsForCapture()
        defer { restoreAnimations() }

        let (container, window) = try await makeSettledSplit(style: .dark)
        defer { window.rootViewController = nil }

        // Same structural gate as the light case — proves the two-column layout in
        // dark too, and guards against a blank/collapsed dark capture.
        assertTwoColumnStructure(container, window: window)
        assertSnapshot(
            matching: container,
            as: .image(
                drawHierarchyInKeyWindow: true,
                size: size,
                traits: UITraitCollection(userInterfaceStyle: .dark)
            ),
            named: "dark"
        )
    }

    // MARK: - Fixture assembly

    /// Seeds a fresh in-memory DB, builds the container, hosts it on a real
    /// on-screen window at `.iPadPro11(.landscape)` size **in the requested style**,
    /// forces the embedded split to regular width (two columns), and waits until it
    /// settles. Each style renders from its own freshly-settled hierarchy so a
    /// light→dark re-render race can never leak a half-updated dark capture — the
    /// override style is applied before the first layout, not toggled mid-test.
    private func makeSettledSplit(
        style: UIUserInterfaceStyle
    ) async throws -> (container: ActivitySummaryReadingSplitViewController, window: UIWindow) {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccount(into: appDatabase)
        try await seedVoteEvents(into: appDatabase, accountId: accountId)

        let preferencesService = SnapshotPreferences.ephemeral()
        let reachabilityMonitor = StaticReachabilityMonitor(isOnline: true)
        let appService = AppService(
            preferencesService: preferencesService,
            appDatabase: appDatabase,
            reachabilityMonitor: reachabilityMonitor,
            webArchiveStore: nil
        )
        let dependencies = SplitDependencies(
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            appDatabase: appDatabase,
            appService: appService,
            appearanceService: AppearanceService(preferencesService: preferencesService),
            diagnosticLog: DiagnosticLog(appDatabase: appDatabase),
            imageService: StaticImageService(),
            linkEmbedService: LinkEmbedService(),
            nodeInfoService: StubNodeInfoService(),
            postContentDetectorService: PostContentDetectorService(),
            preferencesService: preferencesService,
            reachabilityMonitor: reachabilityMonitor
        )

        // `.save`-only initial filter keeps the timeline a pure local (network-free)
        // stream; a fixed `asOf` pins the Summary's heatmap window.
        let container = ActivitySummaryReadingSplitViewController(
            accountKeychainId: keychainId,
            initialFilters: [.save],
            dependencies: dependencies,
            asOf: fixedAsOf
        )

        // A `FixedSafeAreaWindow` (pinned `.zero` safe area) rather than a stock
        // `UIWindow`: `drawHierarchyInKeyWindow: true` renders into whichever window
        // is key, and a stock window's safe area drifts with ambient scene state that
        // an earlier suite can perturb — pinning it makes the capture deterministic
        // across suites (see the "Cross-suite determinism" note above).
        let window = FixedSafeAreaWindow(frame: CGRect(origin: .zero, size: size))
        window.tintColor = lemmyTeal
        window.overrideUserInterfaceStyle = style
        window.rootViewController = container
        window.makeKeyAndVisible()

        // Force the embedded split into a regular-width environment so it expands to
        // two columns deterministically — on an iPhone host the window is compact
        // regardless of its pixel size, which would otherwise collapse the split to
        // a single column (see ActivitySummaryReadingSplitViewControllerTests). The
        // override is set AFTER `makeKeyAndVisible` so the container's `viewDidLoad`
        // has already wired the split delegate that flips the pinned state.
        container.embeddedSplit.traitOverrides.horizontalSizeClass = .regular
        container.embeddedSplit.traitOverrides.verticalSizeClass = .regular
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date())

        try await waitUntilSettled(container: container)

        // Pin every scroll view to its top so a stray non-zero content offset can
        // never leak into the pixel capture — belt-and-braces alongside the safe-area
        // pin. Both columns start scrolled to the top, so this is normally a no-op.
        window.layoutIfNeeded()
        SnapshotDeterminism.pinScrollViewsToTop(in: container.view)
        window.layoutIfNeeded()

        // Snap any in-flight animation to its final (model) value. Animations are
        // already disabled for the capture (see `disableAnimationsForCapture`), but
        // some UIKit controls kick off CATransaction-level implicit animations that
        // ignore `UIView.areAnimationsEnabled` — notably the `UISegmentedControl`
        // selection indicator in the Summary heatmap card, which otherwise settles at
        // a different frame depending on how long the async observation took to land
        // (the first test in a process caught it mid-settle, the second caught it
        // settled). Removing every layer animation makes the capture reflect the
        // final state regardless of timing.
        SnapshotDeterminism.snapAllAnimations(in: window)
        return (container, window)
    }

    // MARK: - Structural assertions (fail loudly in code, not in a pixel diff)

    private func assertTwoColumnStructure(
        _ container: ActivitySummaryReadingSplitViewController,
        window: UIWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Two columns present at regular width.
        XCTAssertFalse(
            container.embeddedSplit.isCollapsed,
            "Expected an EXPANDED two-column split at regular width, but it collapsed to a single column",
            file: file, line: line
        )

        // The Summary dashboard is populated in the SECONDARY (detail) column.
        XCTAssertTrue(
            hierarchyContainsLabel(container.detailNav.view, text: "Lemmy User"),
            "Summary identity ('Lemmy User') not found in the detail column — the Summary side isn't rooting the secondary column",
            file: file, line: line
        )

        // The timeline settled network-free (no spinner still animating anywhere).
        XCTAssertFalse(
            hasAnimatingIndicator(in: container.view),
            "A loading indicator is still animating — the timeline never settled into its deterministic empty state",
            file: file, line: line
        )

        // The "Account" back button is injected onto the primary column's root by
        // the container's UINavigationControllerDelegate; it exists only when the
        // split VC is on screen, so it doubles as a primary-column marker.
        XCTAssertEqual(
            container.activityViewController.navigationItem.leftBarButtonItem?.accessibilityLabel,
            "Back to Account",
            "Primary column 'Back to Account' button missing — the timeline isn't rooting the primary column",
            file: file, line: line
        )

        // Horizontal geometry proof — the load-bearing side-by-side-two-column
        // assertion. The primary (timeline) column anchors the LEFT edge and does
        // not span the full width; the Summary column's CONTENT begins entirely to
        // the RIGHT of it. (Comparing content, not the split's internal container
        // frames: at regular width the secondary nav's *view* legitimately spans the
        // full width while its *content* is inset into the trailing column, so a
        // container-frame non-overlap check would be a false negative.)
        let primaryRect = container.primaryNav.view.convert(container.primaryNav.view.bounds, to: window)
        XCTAssertGreaterThan(primaryRect.width, 0, "Primary column has zero width", file: file, line: line)
        XCTAssertLessThan(
            primaryRect.minX, size.width * 0.1,
            "Primary (timeline) column (minX \(primaryRect.minX)) should anchor near the left edge",
            file: file, line: line
        )
        XCTAssertLessThan(
            primaryRect.maxX, size.width - 1,
            "Primary column (maxX \(primaryRect.maxX)) should occupy a left column, not span the full \(size.width)pt width",
            file: file, line: line
        )

        guard let summaryRect = firstLabelRect(text: "Lemmy User", in: container.detailNav.view, window: window) else {
            XCTFail("Could not locate the Summary identity label to measure the two-column geometry", file: file, line: line)
            return
        }
        XCTAssertGreaterThan(
            summaryRect.minX, primaryRect.maxX - 1,
            "Summary content (minX \(summaryRect.minX)) should sit to the RIGHT of the timeline column (maxX \(primaryRect.maxX)) — proving two side-by-side columns, not a single/overlaid column",
            file: file, line: line
        )
    }

    // MARK: - Settling

    /// Polls until the Summary column has rendered its identity strip and no
    /// loading indicator is still animating anywhere in the container. Suspends the
    /// main actor between polls so the GRDB observation continuations can land.
    /// Fails loudly (never records a blank / mid-load frame) if it never settles.
    private func waitUntilSettled(
        container: ActivitySummaryReadingSplitViewController,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            container.view.layoutIfNeeded()
            let summaryReady = hierarchyContainsLabel(container.detailNav.view, text: "Lemmy User")
            let settled = !hasAnimatingIndicator(in: container.view)
            if summaryReady, settled { return }
        }
        XCTFail(
            "Activity split never settled (Summary identity + stopped spinner) within \(timeout)s — refusing to snapshot a mid-load frame.",
            file: file,
            line: line
        )
    }

    // MARK: - View hierarchy helpers

    private func hierarchyContainsLabel(_ view: UIView, text: String) -> Bool {
        if let label = view as? UILabel, !label.isHidden, label.text?.contains(text) == true {
            return true
        }
        for subview in view.subviews where hierarchyContainsLabel(subview, text: text) {
            return true
        }
        return false
    }

    private func hasAnimatingIndicator(in view: UIView) -> Bool {
        if let indicator = view as? UIActivityIndicatorView {
            return indicator.isAnimating
        }
        return view.subviews.contains { hasAnimatingIndicator(in: $0) }
    }

    /// Window-space frame of the first non-hidden `UILabel` whose text contains
    /// `needle` in the `root` subtree, or `nil` if none is found. Used to measure
    /// where a column's content sits so the two-column geometry can be asserted
    /// from the rendered content rather than the split's internal container frames.
    private func firstLabelRect(text needle: String, in root: UIView, window: UIWindow) -> CGRect? {
        if let label = root as? UILabel, !label.isHidden, label.text?.contains(needle) == true {
            return label.convert(label.bounds, to: window)
        }
        for sub in root.subviews {
            if let rect = firstLabelRect(text: needle, in: sub, window: window) {
                return rect
            }
        }
        return nil
    }

    // MARK: - DB seeding (reuses the SummarySnapshotTests fixture)

    /// Inserts instance → site → person → account, returning the account and person
    /// GRDB row ids. The account is a **signed-out** record with a linked person:
    /// signed-out means `AccountService.lemmyService(…)` never reads the keychain
    /// (which the test bundle can't access), while the linked person still lets the
    /// container resolve the Summary's `accountId` / `personRowId` — so the Summary
    /// populates without any keychain or network dependency.
    private func seedAccount(into appDatabase: AppDatabase) async throws -> (accountId: Int64, personRowId: Int64) {
        try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://lemmy.world', ?)",
                arguments: [Date()]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, Date(), Date()]
            )
            let siteId = db.lastInsertedRowID

            try db.execute(
                sql: """
                    INSERT INTO person (siteId, personId, name, displayName,
                        numberOfPosts, numberOfComments,
                        personCreatedDate, createdAt, updatedAt)
                    VALUES (?, 101, 'lemmy_user', 'Lemmy User', 127, 342, ?, ?, ?)
                    """,
                arguments: [
                    siteId,
                    Date(timeIntervalSince1970: 1_600_000_000), // 2020-09-13 join date
                    Date(),
                    Date(),
                ]
            )
            let personRowId = db.lastInsertedRowID

            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, personId, accountKeychainId,
                         isDefault, isServiceAccount, isSignedOutAccountType,
                         createdAt, updatedAt)
                    VALUES (?, ?, ?, 1, 0, 1, ?, ?)
                    """,
                arguments: [siteId, personRowId, keychainId, Date(), Date()]
            )
            let accountId = db.lastInsertedRowID
            return (accountId, personRowId)
        }
    }

    /// Seeds vote events at fixed UTC epoch seconds within the 18-week window for
    /// `fixedAsOf`, producing visible non-zero heatmap buckets. Identical
    /// distribution to `SummarySnapshotTests.seedVoteEvents`.
    private func seedVoteEvents(into appDatabase: AppDatabase, accountId: Int64) async throws {
        let seedings: [(epochSec: Int64, count: Int)] = [
            (1_742_169_600, 3), // 2025-03-17 Mon
            (1_741_564_800, 7), // 2025-03-10 Mon
            (1_740_355_200, 1), // 2025-02-24 Mon
            (1_737_936_000, 12), // 2025-01-27 Mon
            (1_734_307_200, 2), // 2024-12-16 Mon
        ]
        try await appDatabase.writer.write { db in
            var serverPostId: Int64 = 100
            for (epochSec, count) in seedings {
                for _ in 0..<count {
                    try db.execute(
                        sql: """
                            INSERT INTO voteEvent (accountId, entityType, entityServerId, voteAction, votedAt, communityName)
                            VALUES (?, 'post', ?, 1, ?, 'technology')
                            """,
                        arguments: [accountId, serverPostId, epochSec]
                    )
                    serverPostId += 1
                }
            }
        }
    }
}
