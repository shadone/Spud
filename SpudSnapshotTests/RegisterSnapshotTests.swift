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

/// Snapshots of the redesigned Create-account form and the Pending-review screen
/// in light and dark, pinned to a device config so the references are
/// simulator-independent.
///
/// `SiteListRow` does not carry the instance's registration mode, so the
/// application-required variant is forced via the `#if DEBUG`
/// `setApplicationStateForTesting` seam (mirroring `LoginTwoFactor`'s
/// `setCodeForTesting`) to render the note box, answer field, and "Submit
/// application" CTA deterministically.
@MainActor
final class RegisterSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Pin the host scene's status bar hidden so this nav-hosted capture is
        // immune to an active Simulator GUI session (the 44pt-shift regression).
        // See `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    @MainActor
    private struct SnapshotDependencies: HasVoid, HasAccountService {
        let accountService: AccountServiceType
    }

    private func makeRow(instance: InstanceActorId) -> SiteListRow {
        SiteListRow(
            id: 1,
            instance: instance,
            hostname: "lemmy.world",
            name: "Lemmy World",
            descriptionText: nil,
            iconUrl: nil,
            score: 0,
            usersTotal: nil,
            usersActiveMonth: nil,
            uptimeAllTime: nil,
            isNsfw: false,
            isOpenRegistration: true,
            languageCodes: [],
            tags: []
        )
    }

    /// The redesigned Create-account form, application variant (note box, answer
    /// field, "Submit application" CTA) forced via the DEBUG seam.
    func test_createAccount() throws {
        let instance = try XCTUnwrap(InstanceActorId(from: "https://lemmy.world"))

        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try SnapshotDependencies(
                accountService: AccountService(appDatabase: AppDatabase.inMemory())
            )
            let viewController = RegisterViewController(
                row: makeRow(instance: instance),
                dependencies: dependencies
            )
            viewController.view.tintColor = lemmyTeal
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()
            viewController.setApplicationStateForTesting(
                answer: "Leaving Reddit and want a calmer place to talk tech and self-hosting. I read far more than I post."
            )

            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: navigationController,
                as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    /// The Pending-review screen: application under review, email confirmed.
    func test_pendingReview() throws {
        let instance = try XCTUnwrap(InstanceActorId(from: "https://lemmy.world"))

        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try SnapshotDependencies(
                accountService: AccountService(appDatabase: AppDatabase.inMemory())
            )
            let viewController = PendingReviewViewController(
                hostname: "lemmy.world",
                instance: instance,
                email: "you@email.com",
                emailConfirmationNeeded: false,
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
