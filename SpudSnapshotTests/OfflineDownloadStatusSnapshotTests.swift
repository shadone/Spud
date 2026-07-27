//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// Snapshot of the non-blocking offline-download status pill
/// (`OfflineDownloadStatusView`) at a representative content-phase state
/// ("Saving — 12 of 100"), light + dark. Rendered on a `systemBackground` backdrop
/// with margins so the pill's capsule shape and Liquid Glass material are captured.
///
/// The view is pure presentation — it binds to a fixed `OfflineDownloadProgress`
/// value, with no DB or async observation — so the render is deterministic. As an
/// `.image(size:traits:)`-shaped snapshot it is device- and runtime-sensitive;
/// record on the reference iPhone 17 Pro, iOS 26.3. The progress ring is
/// accent-tinted, so `pinAccent()` fixes the accent (otherwise the sim's
/// persisted accent leaks in).
///
/// The pill's background became a real `glassEffect` (Liquid Glass) since
/// Task 16 of the Liquid Glass conversion. Like `UIVisualEffectView`, SwiftUI's
/// glass material only composites against a live on-screen backdrop — captured
/// offscreen (the previous `.image(size:traits:)` strategy, which draws via
/// `layer.render(in:)`) it renders blank. This suite hosts the view on a real,
/// key ``FixedSafeAreaWindow`` and captures with `drawHierarchyInKeyWindow: true`
/// instead, mirroring `SummarySnapshotTests`' `UIHostingController`-on-a-window
/// pattern (the same fix `ToastSnapshotTests` applies for its own
/// `UIVisualEffectView`-backed pill).
@MainActor
final class OfflineDownloadStatusSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The ring's arc uses the process-global accent; pin it so the render
        // doesn't depend on the sim's persisted accent preference. See
        // `SnapshotDeterminism.pinAccent()`.
        SnapshotDeterminism.pinAccent()
        // Pin the host scene's status bar hidden so this on-screen
        // (`drawHierarchyInKeyWindow`) capture is immune to the sim's persisted
        // orientation state. See `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    func test_downloadingContent() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewModel = OfflineDownloadProgressViewModel(
                progress: OfflineDownloadProgress(
                    phase: .downloadingContent,
                    postsFetched: 100,
                    totalPosts: 100,
                    itemsCompleted: 12
                ),
                onCancel: { }
            )
            let size = CGSize(width: 390, height: 120)
            let view = OfflineDownloadStatusView(viewModel: viewModel)
                .padding(20)
                .frame(width: size.width, height: size.height)
                .background(Color(uiColor: .systemBackground))

            let host = UIHostingController(rootView: view)
            host.view.frame = CGRect(origin: .zero, size: size)

            // Host on a real, key window so the glass material actually
            // composites (see the class doc comment) — mirrors
            // `SummarySnapshotTests`' `hostInWindow` helper.
            let window = FixedSafeAreaWindow(frame: CGRect(origin: .zero, size: size))
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date())
            defer { window.rootViewController = nil }

            assertSnapshot(
                matching: host,
                as: .image(
                    drawHierarchyInKeyWindow: true,
                    size: size,
                    traits: UITraitCollection(traitsFrom: [
                        UITraitCollection(userInterfaceStyle: style),
                        SnapshotDeterminism.contentSizeTrait,
                    ])
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
