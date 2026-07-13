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

/// Snapshots of the two SwiftUI session-reauth surfaces:
/// - `AccountView`'s prominent "Session expired" row, shown only when the active
///   account's `sessionNeedsReauth` is set (and absent otherwise).
/// - `AccountSwitcherView`'s per-row "Re-login" affordance, shown only on a
///   flagged row (a clean row alongside it must not show one).
///
/// Both views drive their content from async GRDB observations, so each test
/// seeds an in-memory DB first, then polls until the observation populates
/// before rendering (failing loudly rather than recording a blank).
/// `.image(size:traits:)` is device- and runtime-sensitive — record on the
/// reference iPhone 17 Pro, iOS 26.3.
@MainActor
final class SessionReauthSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))

    // MARK: - AccountView

    func test_accountView_sessionNeedsReauth() async throws {
        for needsReauth in [true, false] {
            let appDatabase = try AppDatabase.inMemory()
            try await seedSignedInAccount(into: appDatabase, sessionNeedsReauth: needsReauth)

            let accountService = AccountService(appDatabase: appDatabase)
            let viewModel = AccountViewModel(
                accountService: accountService,
                appDatabase: appDatabase
            )

            // `apply(record:)` sets `sessionNeedsReauth` synchronously from the same
            // `observeDefaultAccount` emission that seeds `isSignedIn`/`ownPerson`, so
            // waiting for the profile to resolve (as the base Account snapshot does)
            // is enough to guarantee the flag reflects the seeded row too.
            try await waitUntil {
                viewModel.isSignedIn
                    && !viewModel.handle.isEmpty
                    && viewModel.ownPerson != nil
            }

            let view = AccountView(
                viewModel: viewModel,
                accent: teal,
                onEditProfile: { },
                onReauth: { },
                onSwitchAccount: { },
                onOpenSaved: { },
                onOpenActivity: { },
                onOpenYourPosts: { },
                onOpenYourComments: { },
                onOpenDraftsOutbox: { },
                onLogout: { }
            )
            .environment(\.imageService, StaticImageService())

            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 844)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: .light),
                    SnapshotDeterminism.contentSizeTrait,
                ])),
                named: needsReauth ? "flagged" : "clean"
            )
        }
    }

    // MARK: - AccountSwitcherView

    func test_accountSwitcher_sessionNeedsReauth() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()
            try await seedSwitcherAccounts(into: appDatabase)

            let viewModel = AccountSwitcherViewModel(appDatabase: appDatabase)

            try await waitUntil { viewModel.rows.count == 2 }

            let view = AccountSwitcherView(
                viewModel: viewModel,
                accent: teal,
                onSelect: { _ in },
                onRemove: { _ in },
                onReauth: { _ in },
                onAddAccount: { },
                onBrowseAnonymously: { }
            )

            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 844)
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

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Observation did not populate within \(timeout)s", line: line)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Seeds an instance + site + person + a default signed-in account, with
    /// `sessionNeedsReauth` set as requested, so the view model's three
    /// observations (default account, own person, profile row) all resolve to a
    /// populated header.
    private func seedSignedInAccount(into appDatabase: AppDatabase, sessionNeedsReauth: Bool) async throws {
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
                accountKeychainId: "snapshot-reauth",
                isDefault: true,
                isSignedOutAccountType: false,
                sessionNeedsReauth: sessionNeedsReauth
            )
            try account.insert(db)
        }
    }

    /// Seeds two signed-in accounts on different instances: the default account
    /// clean, and a second (non-active) account flagged `sessionNeedsReauth`, so
    /// the switcher's per-row "Re-login" affordance renders on exactly one row.
    private func seedSwitcherAccounts(into appDatabase: AppDatabase) async throws {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

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
                isSignedOutAccountType: false,
                sessionNeedsReauth: false
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
                isSignedOutAccountType: false,
                sessionNeedsReauth: true
            )
            try graceAccount.insert(db)
        }
    }
}
