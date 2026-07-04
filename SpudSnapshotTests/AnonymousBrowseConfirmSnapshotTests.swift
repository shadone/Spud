//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUtilKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the anonymous-browse confirmation screen in light and dark,
/// pinned to a device config so the references are simulator-independent.
@MainActor
final class AnonymousBrowseConfirmSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    /// The confirmation screen only stores an `AccountService` (touched on the
    /// "Start browsing" tap, not while rendering), so an in-memory account
    /// service is enough.
    @MainActor
    private struct SnapshotDependencies: HasAccountService {
        let accountService: AccountServiceType
    }

    func test_confirm() throws {
        let instance = try XCTUnwrap(InstanceActorId(from: "https://lemmy.ca"))

        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()
            let dependencies = SnapshotDependencies(
                accountService: AccountService(appDatabase: appDatabase)
            )
            let viewController = AnonymousBrowseConfirmViewController(
                instance: instance,
                hostname: "lemmy.ca",
                dependencies: dependencies
            )
            viewController.view.tintColor = lemmyTeal
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: navigationController,
                as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
