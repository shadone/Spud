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
/// with margins so the pill's capsule shape, border, and shadow are captured.
///
/// The view is pure presentation — it binds to a fixed `OfflineDownloadProgress`
/// value, with no DB or async observation — so the render is deterministic. As an
/// `.image(size:traits:)` snapshot it is device- and runtime-sensitive; record on
/// the reference iPhone 17 Pro, iOS 26.3. The progress ring is accent-tinted, so
/// `pinAccent()` fixes the accent (otherwise the sim's persisted accent leaks in).
@MainActor
final class OfflineDownloadStatusSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The ring's arc uses the process-global accent; pin it so the render
        // doesn't depend on the sim's persisted accent preference. See
        // `SnapshotDeterminism.pinAccent()`.
        SnapshotDeterminism.pinAccent()
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
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: style),
                    SnapshotDeterminism.contentSizeTrait,
                ])),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
