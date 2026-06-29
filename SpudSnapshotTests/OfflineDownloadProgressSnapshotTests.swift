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

/// Snapshot of the offline-download progress sheet (`OfflineDownloadProgressView`)
/// at a representative content-phase state ("Saving — 12 of 100"), light + dark.
///
/// The view is pure presentation — it binds to a fixed `OfflineDownloadProgress`
/// value, with no DB or async observation — so the render is deterministic. As an
/// `.image(size:traits:)` snapshot it is device- and runtime-sensitive; record on
/// the reference iPhone 17 Pro, iOS 26.3.
@MainActor
final class OfflineDownloadProgressSnapshotTests: XCTestCase {
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
            let view = OfflineDownloadProgressView(viewModel: viewModel)

            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 260)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
