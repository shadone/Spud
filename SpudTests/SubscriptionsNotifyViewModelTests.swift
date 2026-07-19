//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
@testable import Spud
@testable import SpudDataKit

// MARK: - Test doubles

/// Satisfies `ReminderService`'s init — a real `ReminderService` is built
/// against the test's own in-memory `AppDatabase` below (it's a concrete
/// actor, not a protocol, so it can't be swapped for a call-recording spy).
/// Mirrors `InboxViewModelRemoveReminderTests.NoOpReminderScheduler`; its
/// calls are never asserted on here, only the durable `reminder` rows are.
private actor NoOpNotifyReminderScheduler: ReminderNotificationScheduling {
    func requestAuthorization() async -> Bool {
        true
    }

    func authorizationGranted() async -> Bool {
        true
    }

    func schedule(requestId _: String, fireAt _: Date, content _: ReminderNotificationContent) async { }
    func postNow(requestId _: String, content _: ReminderNotificationContent) async { }
    func cancel(requestId _: String) async { }
}

/// Minimal `AccountServiceType` returning a real, test-backed `ReminderService`
/// (for `toggleNotify`) and a fixed home instance (so `AccountScope.
/// instanceActorId` resolves, which `toggleNotify(_ item:)` needs for its
/// `instanceHost`). `lemmyService` traps — neither `toggleNotify` overload
/// under test ever reaches it.
@MainActor
private final class FakeNotifyAccountService: AccountServiceType {
    let stubbedReminderService: ReminderService
    let instance: InstanceActorId?

    init(reminderService: ReminderService, instance: InstanceActorId?) {
        stubbedReminderService = reminderService
        self.instance = instance
    }

    func reminderService(forAccountKeychainId _: String) -> ReminderService {
        stubbedReminderService
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        fatalError("lemmyService not stubbed - toggleNotify should never reach it")
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        instance
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        .allAvailable
    }

    // MARK: Unused stubs

    func accountForSignedOut(forInstance _: InstanceActorId, isServiceAccount _: Bool) -> String {
        ""
    }

    func signInAsSignedOut(atInstance _: InstanceActorId) { }
    #if DEBUG
    func seedSignedInDefaultAccount(atInstance _: InstanceActorId) { }
    #endif
    func login(atInstance _: InstanceActorId, username _: String, password _: String, totp2faToken _: String?) async throws { }
    func reauthenticate(keychainId _: String, username _: String, password _: String, totp2faToken _: String?) async throws { }
    func username(forAccountKeychainId _: String) -> String? {
        nil
    }

    func register(atInstance _: InstanceActorId, username _: String, email _: String?, password _: String, passwordVerify _: String, showNsfw _: Bool, captchaUuid _: String?, captchaAnswer _: String?, answer _: String?) async throws -> AccountServiceRegisterResult {
        fatalError()
    }

    func passwordReset(atInstance _: InstanceActorId, email _: String) async throws { }
    func logout(forAccountKeychainId _: String) { }
    func removeAccount(forAccountKeychainId _: String) { }
    func currentDefaultAccountKeychainId() -> String? {
        nil
    }

    func isSignedOut(forAccountKeychainId _: String) -> Bool {
        false
    }

    func setDefaultAccount(forAccountKeychainId _: String) { }
    func accountKeychainId(forInstance _: InstanceActorId) -> String {
        ""
    }

    func defaultListingType(forAccountKeychainId _: String) -> Lemmy.ListingType {
        .All
    }

    func defaultSortType(forAccountKeychainId _: String) -> Lemmy.SortType {
        .Hot
    }

    func setDefaultSortType(_: Lemmy.SortType, forAccountKeychainId _: String) { }

    func refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId _: String) { }

    func createFeed(type _: FeedType, forAccountKeychainId _: String) async throws -> FeedHandle {
        fatalError()
    }

    func defaultFeedHandle(forAccountKeychainId _: String) -> FeedHandle? {
        nil
    }
}

// MARK: - Tests

/// Exercises `SubscriptionsViewModel`'s Task 6 notify wiring: the meta-row
/// bell (`toggleNotify(_ item:)` / `notifyingCommunityIds`) and the
/// subscribed-list context-menu item (`toggleNotify(for row:)` /
/// `isNotifying(_ row:)`). Both round-trip through a REAL `ReminderService`
/// over an in-memory `AppDatabase` (mirrors `InboxViewModelRemoveReminderTests`),
/// asserting on the durable `reminder` rows via `AppDatabase.reminderSync`
/// rather than a spy — this is also `observeCommunityFollowServerIds`
/// (Task 1)'s first real coverage.
@MainActor
struct SubscriptionsNotifyViewModelTests {
    private let keychainId = "kc-notify-test"
    private let instanceHost = "tchncs.de"
    private let communityActorId = "https://tchncs.de/c/meta"
    private let communityServerId: Int64 = 42

    /// `AccountRecord.siteId` is a NOT NULL foreign key to `site`, which in
    /// turn has a NOT NULL foreign key to `instance` — seeding a bare account
    /// requires standing up an instance and a site first (mirrors
    /// `SubscriptionsMetaSectionViewModelTests.makeAccount`).
    private func makeAccount(appDatabase: AppDatabase) throws -> Int64 {
        try appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://\(instanceHost)")
            try instance.insert(db)

            var site = try SiteRecord(instanceId: #require(instance.id))
            try site.insert(db)

            var account = try AccountRecord(
                siteId: #require(site.id),
                accountKeychainId: keychainId
            )
            try account.insert(db)
            return try #require(account.id)
        }
    }

    private func makeViewModel(appDatabase: AppDatabase, accountId: Int64) -> SubscriptionsViewModel {
        let reminderService = ReminderService(
            accountId: accountId,
            appDatabase: appDatabase,
            scheduler: NoOpNotifyReminderScheduler()
        )
        let accountService = FakeNotifyAccountService(
            reminderService: reminderService,
            instance: InstanceActorId(from: "https://\(instanceHost)")
        )
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        return SubscriptionsViewModel(
            accountRowId: accountId,
            isSignedIn: true,
            appDatabase: appDatabase,
            accountScope: scope,
            metaCommunityService: nil,
            onFeedRequested: { _ in },
            onExploreRequested: { }
        )
    }

    private func makeItem(isFavorite: Bool = false) -> MetaCommunityListItem {
        MetaCommunityListItem(
            id: communityServerId, name: "meta", title: "Meta", communityActorId: communityActorId,
            iconUrl: nil, confidence: .high, subscribedState: .notSubscribed, isFavorite: isFavorite
        )
    }

    /// Polls a condition until it's true or a couple of seconds pass — the VM's
    /// observations (`notifyingCommunityIds`) and `toggleNotify`'s durable write
    /// both land asynchronously off a detached `Task`.
    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while await !condition() {
            if Date() > deadline { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: toggleNotify(_ item:) — meta-row bell

    @Test
    func toggleNotify_item_notNotifying_insertsFollowRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try makeAccount(appDatabase: appDatabase)
        let vm = makeViewModel(appDatabase: appDatabase, accountId: accountId)

        #expect(appDatabase.reminderSync(
            accountId: accountId, postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
        ) == nil)

        vm.toggleNotify(makeItem())

        await waitUntil {
            appDatabase.reminderSync(
                accountId: accountId, postServerId: communityServerId,
                rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
            ) != nil
        }

        let row = try #require(appDatabase.reminderSync(
            accountId: accountId, postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
        ))
        #expect(row.apId == communityActorId)
        #expect(row.communityName == "meta")
        #expect(row.titleSnapshot == "Meta")
        #expect(row.instanceHost == instanceHost)
        #expect(row.kind == ReminderRecord.Kind.communityPosts.rawValue)

        // `notifyingCommunityIds` (Task 1's `observeCommunityFollowServerIds`,
        // exercised live for the first time here) picks up the new row too.
        await waitUntil { vm.notifyingCommunityIds.contains(communityServerId) }
        #expect(vm.notifyingCommunityIds.contains(communityServerId))
    }

    @Test
    func toggleNotify_item_notifying_removesFollowRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try makeAccount(appDatabase: appDatabase)
        let vm = makeViewModel(appDatabase: appDatabase, accountId: accountId)

        // Establish the follow first, and wait for the VM's own observation to
        // catch up - `toggleNotify` reads `notifyingCommunityIds` (not the DB)
        // to decide set-vs-remove, mirroring the real bell-tap flow where the
        // second tap only flips because the first tap's write round-tripped
        // through the live observation.
        vm.toggleNotify(makeItem())
        await waitUntil { vm.notifyingCommunityIds.contains(communityServerId) }

        vm.toggleNotify(makeItem())

        await waitUntil {
            appDatabase.reminderSync(
                accountId: accountId, postServerId: communityServerId,
                rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
            ) == nil
        }

        #expect(appDatabase.reminderSync(
            accountId: accountId, postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
        ) == nil)

        await waitUntil { !vm.notifyingCommunityIds.contains(communityServerId) }
        #expect(!vm.notifyingCommunityIds.contains(communityServerId))
    }

    // MARK: toggleNotify(for row:) / isNotifying(_ row:) — subscribed-list menu

    /// `SubscriptionsCommunityRow.id` is the row's LOCAL primary key, distinct
    /// from `communityServerId` (the server-assigned id `ReminderService`
    /// keys on) - this fixture deliberately gives them different values so a
    /// regression back to using `row.id` fails loudly instead of silently
    /// happening to work.
    private func makeRow(favorite: Bool = false) -> SubscriptionsCommunityRow {
        SubscriptionsCommunityRow(
            id: 999,
            name: "meta",
            instanceActorId: InstanceActorId(from: "https://\(instanceHost)")!,
            communityActorId: communityActorId,
            communityServerId: communityServerId,
            isFavorite: favorite
        )
    }

    @Test
    func toggleNotify_forRow_notNotifying_insertsFollowRowKeyedByCommunityServerId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try makeAccount(appDatabase: appDatabase)
        let vm = makeViewModel(appDatabase: appDatabase, accountId: accountId)
        let row = makeRow()

        #expect(!vm.isNotifying(row))

        vm.toggleNotify(for: row)

        await waitUntil {
            appDatabase.reminderSync(
                accountId: accountId, postServerId: communityServerId,
                rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
            ) != nil
        }

        // Keyed by `communityServerId` (42), NOT the row's local `id` (999).
        let followRow = try #require(appDatabase.reminderSync(
            accountId: accountId, postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
        ))
        #expect(followRow.apId == communityActorId)
        #expect(followRow.instanceHost == instanceHost)
        #expect(appDatabase.reminderSync(
            accountId: accountId, postServerId: 999,
            rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
        ) == nil)

        await waitUntil { vm.isNotifying(row) }
        #expect(vm.isNotifying(row))
    }

    @Test
    func toggleNotify_forRow_notifying_removesFollowRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try makeAccount(appDatabase: appDatabase)
        let vm = makeViewModel(appDatabase: appDatabase, accountId: accountId)
        let row = makeRow()

        vm.toggleNotify(for: row)
        await waitUntil { vm.isNotifying(row) }

        vm.toggleNotify(for: row)

        await waitUntil { !vm.isNotifying(row) }
        #expect(!vm.isNotifying(row))
        #expect(appDatabase.reminderSync(
            accountId: accountId, postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel, kind: ReminderRecord.Kind.communityPosts.rawValue
        ) == nil)
    }
}
