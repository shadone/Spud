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

/// Screen snapshots of the redesigned login form (instance header card, the
/// username / password fields, the accent "Log in" CTA, and the outlined
/// "browse anonymously" row) in light and dark, plus the inline password error
/// state.
///
/// Rendered at a pinned `ViewImageConfig` (iPhone 13 Pro size/scale/safe-area)
/// so the references are device-independent — they record and verify identically
/// on any simulator. The fixture leaves `iconUrl` nil so the avatar renders its
/// deterministic placeholder with no async image loading. The brand "Lemmy"
/// teal is pinned on the root so the accent-tinted controls match the runtime
/// window `tintColor`.
@MainActor
final class LoginScreenSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    @MainActor
    private struct SnapshotDependencies: HasVoid, HasImageService, HasAccountService, HasAlertService {
        let imageService: ImageServiceType
        let accountService: AccountServiceType
        let alertService: AlertServiceType
    }

    private func makeDependencies() throws -> SnapshotDependencies {
        let appDatabase = try AppDatabase.inMemory()
        return SnapshotDependencies(
            imageService: StaticImageService(),
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService()
        )
    }

    private func makeRow() -> SiteListRow {
        SiteListRow(
            id: 1,
            instance: InstanceActorId(from: "lemmy.world")!,
            hostname: "lemmy.world",
            name: "Lemmy World",
            descriptionText: "The largest general-purpose Lemmy server. Big, fast and well-moderated.",
            iconUrl: nil
        )
    }

    private func makeViewController() throws -> LoginViewController {
        let dependencies = try makeDependencies()
        let viewController = LoginViewController(row: makeRow(), dependencies: dependencies)
        viewController.view.tintColor = lemmyTeal
        return viewController
    }

    private func assertScreens(
        configure: (LoginViewController) -> Void = { _ in },
        testName: String = #function,
        line: UInt = #line
    ) throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewController = try makeViewController()
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.view.tintColor = lemmyTeal
            // Force the view hierarchy to load before mutating it.
            viewController.loadViewIfNeeded()
            configure(viewController)
            assertSnapshot(
                matching: navigationController,
                as: .image(on: .iPhone13Pro, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    func test_loginForm() throws {
        try assertScreens()
    }

    func test_loginForm_error() throws {
        try assertScreens { viewController in
            viewController.passwordField.errorText = NSLocalizedString(
                "Incorrect username or password.",
                comment: ""
            )
        }
    }
}
