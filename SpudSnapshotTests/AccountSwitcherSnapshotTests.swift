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

/// Full-screen snapshot of the account-switcher sheet content
/// (`AccountSwitcherView`): the centered "Accounts" title over the "Signed in"
/// section (two accounts, one active with the filled radio check), the
/// "Anonymous" section (one signed-out account + the federation footnote), and
/// the two accent action rows.
///
/// The view reads its rows from an `@Observable` `AccountSwitcherViewModel`, so
/// the test seeds an in-memory DB (two signed-in accounts + one anonymous), then
/// polls until `viewModel.rows` populates before rendering (failing loudly rather
/// than recording a blank). Avatars use nil URLs -> the deterministic hue-tile
/// fallback, keeping the render stable. `.image(size:traits:)` is device- and
/// runtime-sensitive — record on the reference iPhone 17 Pro, iOS 26.3.
@MainActor
final class AccountSwitcherSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))

    func test_accountSwitcher_populated() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()
            try await seedAccounts(into: appDatabase)

            let viewModel = AccountSwitcherViewModel(appDatabase: appDatabase)

            // Rows arrive via the async DB observation; wait for all three seeded
            // accounts to land before rendering.
            try await waitUntil { viewModel.rows.count == 3 }

            let view = AccountSwitcherView(
                viewModel: viewModel,
                accent: teal,
                onSelect: { _ in },
                onRemove: { _ in },
                onAddAccount: { },
                onBrowseAnonymously: { }
            )

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
                XCTFail("Account switcher rows did not populate within \(timeout)s", line: line)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Seeds two signed-in accounts (the first default/active, with a display
    /// name that differs from its username so the `@username@instance` handle is
    /// exercised) plus one anonymous account, so the view model's observation
    /// emits all three rows across both sections.
    private func seedAccounts(into appDatabase: AppDatabase) async throws {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            // Display name "Ada Lovelace" but username "ada" — the handle line must
            // render `@ada@lemmy.world`, never `@Ada Lovelace@lemmy.world`.
            var ada = PersonRecord(
                siteId: site.id!,
                personId: 1,
                name: "ada",
                displayName: "Ada Lovelace",
                avatarUrl: nil,
                bio: nil,
                actorId: "https://lemmy.world/u/ada",
                isLocal: true,
                numberOfPosts: 0,
                numberOfComments: 0
            )
            try ada.insert(db)
            var adaAccount = AccountRecord(
                siteId: site.id!,
                personId: ada.id!,
                accountKeychainId: "kc-ada",
                isDefault: true,
                isSignedOutAccountType: false
            )
            try adaAccount.insert(db)

            var beehawInstance = InstanceRecord(actorId: "https://beehaw.org")
            try beehawInstance.insert(db)
            var beehawSite = SiteRecord(instanceId: beehawInstance.id!)
            try beehawSite.insert(db)
            var grace = PersonRecord(
                siteId: beehawSite.id!,
                personId: 2,
                name: "grace",
                displayName: nil,
                avatarUrl: nil,
                bio: nil,
                actorId: "https://beehaw.org/u/grace",
                isLocal: true,
                numberOfPosts: 0,
                numberOfComments: 0
            )
            try grace.insert(db)
            var graceAccount = AccountRecord(
                siteId: beehawSite.id!,
                personId: grace.id!,
                accountKeychainId: "kc-grace",
                isDefault: false,
                isSignedOutAccountType: false
            )
            try graceAccount.insert(db)

            var anonInstance = InstanceRecord(actorId: "https://discuss.tchncs.de")
            try anonInstance.insert(db)
            var anonSite = SiteRecord(instanceId: anonInstance.id!)
            try anonSite.insert(db)
            var anonAccount = AccountRecord(
                siteId: anonSite.id!,
                personId: nil,
                accountKeychainId: "kc-anon",
                isDefault: false,
                isSignedOutAccountType: true
            )
            try anonAccount.insert(db)
        }
    }
}
