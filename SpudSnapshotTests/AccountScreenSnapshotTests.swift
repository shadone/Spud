//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import SnapshotTesting
import SpudDataKit
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// Full-screen snapshot of the signed-in Account tab (`AccountView`): the
/// tappable profile header (display name + monospaced handle + chevron) over the
/// grouped account-action rows (Switch account, Saved / Activity / Your posts /
/// Your comments, Log out).
///
/// `AccountViewModel` fills the header from **async** GRDB observations
/// (`observeDefaultAccount`, `observePersonProfile`, `observeAccounts`), so the
/// DB is seeded first, then the test polls until the header populates before
/// rendering (failing loudly rather than recording a blank). `.image(size:traits:)`
/// is device- and runtime-sensitive — record on the reference iPhone 17 Pro, iOS 26.3.
@MainActor
final class AccountScreenSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))
    private let keychainId = "snapshot-signed-in"

    func test_accountSignedIn_populated() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()
            try await seedSignedInAccount(into: appDatabase)

            let accountService = AccountService(appDatabase: appDatabase)
            let viewModel = AccountViewModel(
                accountService: accountService,
                appDatabase: appDatabase
            )

            // The header arrives via async observations; wait for the profile to
            // resolve (then the list is no longer the bring-up placeholder).
            try await waitUntil {
                viewModel.isSignedIn
                    && !viewModel.handle.isEmpty
                    && viewModel.ownPerson != nil
            }

            let view = AccountView(
                viewModel: viewModel,
                accent: teal,
                onEditProfile: { },
                onSwitchAccount: { },
                onOpenSaved: { },
                onOpenActivity: { },
                onOpenYourPosts: { },
                onOpenYourComments: { },
                onLogout: { }
            )
            .environment(\.imageService, StaticImageService())

            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 844)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Account header did not populate within \(timeout)s", line: line)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Seeds an instance + site + person + a default signed-in account whose
    /// `personId` points at the person, so all three observations the view model
    /// drives resolve to a populated header.
    private func seedSignedInAccount(into appDatabase: AppDatabase) async throws {
        let keychainId = keychainId
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var person = PersonRecord(
                siteId: site.id!,
                personId: 42,
                name: "ada",
                displayName: "Ada Lovelace",
                avatarUrl: nil,
                bio: "First programmer.",
                actorId: "https://lemmy.world/u/ada",
                isLocal: true,
                numberOfPosts: 12,
                numberOfComments: 87
            )
            try person.insert(db)

            var account = AccountRecord(
                siteId: site.id!,
                personId: person.id!,
                accountKeychainId: keychainId,
                isDefault: true,
                isSignedOutAccountType: false
            )
            try account.insert(db)
        }
    }
}
