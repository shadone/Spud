//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

/// Tests for `AccountService.logout`: it removes the account row from the
/// database and switches the default to another registered account, or to the
/// signed-out account on the same instance when no other account exists.
@MainActor
struct AccountServiceLogoutTests {
    private var appDatabase: AppDatabase
    private var sut: AccountService

    /// Shared across every account's `ReminderService` (mirrors production:
    /// `AccountService` builds one scheduler lazily and reuses it for every
    /// account) - kept as a property so tests can inspect `cancelCalls` after
    /// driving `logout`/`removeAccount`.
    private let reminderScheduler = ReminderServiceTests.FakeReminderNotificationScheduler()

    init() throws {
        appDatabase = try AppDatabase.inMemory()
        // `logout`/`removeAccount` now resolve (and tear down) this account's
        // `ReminderService` (Phase 4), which lazily builds the shared
        // `ReminderNotificationScheduling` on first access - the default
        // `UNReminderNotificationScheduler` calls
        // `UNUserNotificationCenter.current()`, which crashes the bare
        // `xctest` process these tests run under (no hosting app). Inject the
        // fake instead, mirroring every other `ReminderService` test.
        let scheduler = reminderScheduler
        sut = AccountService(
            appDatabase: appDatabase,
            makeReminderNotificationScheduler: { scheduler }
        )
    }

    /// Seeds one instance/site with the given accounts. Returns the keychain
    /// ids in insertion order.
    @discardableResult
    private func seed(
        accounts: [(keychainId: String, isSignedOut: Bool, isDefault: Bool)]
    ) async throws -> Int64 {
        try await appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            for account in accounts {
                var record = AccountRecord(
                    siteId: site.id!,
                    accountKeychainId: account.keychainId,
                    isDefault: account.isDefault,
                    isSignedOutAccountType: account.isSignedOut
                )
                try record.insert(db)
            }
            return site.id!
        }
    }

    private func accountExists(keychainId: String) throws -> Bool {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchCount(db) > 0
        }
    }

    private func defaultKeychainId() throws -> String? {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("isDefault") == true)
                .fetchOne(db)?
                .accountKeychainId
        }
    }

    private func reminderRowCount(accountId: Int64) async throws -> Int {
        try await appDatabase.writer.read { db in
            try ReminderRecord.filter(Column("accountId") == accountId).fetchCount(db)
        }
    }

    /// `logout`/`removeAccount` are synchronous and tear down reminders
    /// fire-and-forget in a detached `Task` (see their doc comments), so
    /// there's no handle to `await` directly - poll with a short bound
    /// instead of asserting immediately after the synchronous call returns.
    private func waitUntilReminderRowCount(accountId: Int64, is expected: Int) async throws {
        for _ in 0..<50 {
            if try await reminderRowCount(accountId: accountId) == expected { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test
    func logoutRemovesAccountRow() async throws {
        try await seed(accounts: [
            (keychainId: "signed-in-1", isSignedOut: false, isDefault: true),
            (keychainId: "signed-out", isSignedOut: true, isDefault: false),
        ])

        sut.logout(forAccountKeychainId: "signed-in-1")

        #expect(try !accountExists(keychainId: "signed-in-1"), "logout should delete the account row")
    }

    @Test
    func logoutSwitchesDefaultToAnotherSignedInAccount() async throws {
        try await seed(accounts: [
            (keychainId: "signed-in-1", isSignedOut: false, isDefault: true),
            (keychainId: "signed-in-2", isSignedOut: false, isDefault: false),
            (keychainId: "signed-out", isSignedOut: true, isDefault: false),
        ])

        sut.logout(forAccountKeychainId: "signed-in-1")

        // The remaining signed-in account is preferred over the signed-out one.
        #expect(try defaultKeychainId() == "signed-in-2")
        #expect(try accountExists(keychainId: "signed-in-2"))
        #expect(try accountExists(keychainId: "signed-out"))
    }

    @Test
    func logoutFallsBackToSignedOutAccountWhenNoOtherSignedInAccount() async throws {
        try await seed(accounts: [
            (keychainId: "signed-in-1", isSignedOut: false, isDefault: true),
            (keychainId: "signed-out", isSignedOut: true, isDefault: false),
        ])

        sut.logout(forAccountKeychainId: "signed-in-1")

        #expect(try !accountExists(keychainId: "signed-in-1"))
        #expect(try defaultKeychainId() == "signed-out", "logout should fall back to the signed-out account")
    }

    @Test
    func logoutIsNoOpForSignedOutAccount() async throws {
        try await seed(accounts: [
            (keychainId: "signed-out", isSignedOut: true, isDefault: true),
        ])

        sut.logout(forAccountKeychainId: "signed-out")

        #expect(try accountExists(keychainId: "signed-out"), "logout should not remove a signed-out account")
    }

    /// End-to-end coverage of the Phase-4 wiring: `logout` resolves this
    /// account's `ReminderService` and tears it down (deletes its reminder
    /// rows, cancels the stored OS notification request) - not just that the
    /// account row itself goes away.
    @Test
    func logoutCancelsAccountsReminders() async throws {
        try await seed(accounts: [
            (keychainId: "signed-in-1", isSignedOut: false, isDefault: true),
            (keychainId: "signed-out", isSignedOut: true, isDefault: false),
        ])
        let accountId = try #require(appDatabase.accountRowIdSync(forKeychainId: "signed-in-1"))
        _ = try await appDatabase.upsertReminder(ReminderRecord(
            accountId: accountId,
            postServerId: 100,
            apId: "https://example.com/post/100",
            kind: ReminderRecord.Kind.time.rawValue,
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: ReminderRecord.Status.scheduled.rawValue,
            notificationRequestId: "reminder-\(accountId)-100-0-time",
            titleSnapshot: "A post",
            communityName: "news",
            instanceHost: "example.com"
        ))

        sut.logout(forAccountKeychainId: "signed-in-1")

        try await waitUntilReminderRowCount(accountId: accountId, is: 0)
        let cancelCalls = await reminderScheduler.cancelCalls
        #expect(cancelCalls == ["reminder-\(accountId)-100-0-time"])
    }

    /// Mirrors `logoutCancelsAccountsReminders` for `removeAccount`, which
    /// removes signed-out accounts too (unlike `logout`).
    @Test
    func removeAccountCancelsAccountsReminders() async throws {
        try await seed(accounts: [
            (keychainId: "signed-out", isSignedOut: true, isDefault: true),
        ])
        let accountId = try #require(appDatabase.accountRowIdSync(forKeychainId: "signed-out"))
        _ = try await appDatabase.upsertReminder(ReminderRecord(
            accountId: accountId,
            postServerId: 200,
            apId: "https://example.com/post/200",
            kind: ReminderRecord.Kind.time.rawValue,
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: ReminderRecord.Status.scheduled.rawValue,
            notificationRequestId: "reminder-\(accountId)-200-0-time",
            titleSnapshot: "A post",
            communityName: "news",
            instanceHost: "example.com"
        ))

        sut.removeAccount(forAccountKeychainId: "signed-out")

        try await waitUntilReminderRowCount(accountId: accountId, is: 0)
        let cancelCalls = await reminderScheduler.cancelCalls
        #expect(cancelCalls == ["reminder-\(accountId)-200-0-time"])
    }
}
