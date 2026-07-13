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

/// Satisfies `ReminderService`'s init - a real `ReminderService` is built
/// against the test's own in-memory `AppDatabase` below (it's a concrete
/// actor, not a protocol, so it can't be replaced with a spy the way
/// `LemmyServiceType` is elsewhere in this file's sibling tests). This
/// scheduler's calls are never asserted on here; the assertions are all on
/// the durable `reminder` rows, mirroring
/// `ReminderServiceActivityTests.timeAndActivityReminderOnSamePostAreIndependent`.
private actor NoOpReminderScheduler: ReminderNotificationScheduling {
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
/// for `reminderService(forAccountKeychainId:)` - every other requirement
/// traps, since `InboxViewModel.removeReminder` only ever reaches
/// `accountScope.reminderService`.
@MainActor
private final class FakeRemoveReminderAccountService: AccountServiceType {
    let stubbedReminderService: ReminderService

    init(reminderService: ReminderService) {
        stubbedReminderService = reminderService
    }

    func reminderService(forAccountKeychainId _: String) -> ReminderService {
        stubbedReminderService
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        trap()
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        .allAvailable
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        nil
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
}

/// No-op alert double - a correct kind-aware dispatch never reaches the error
/// path, so a test seeing a handled error here signals the fix regressed.
private final class NoOpAlertService: AlertServiceType, @unchecked Sendable {
    func handle(_: Error, for _: AlertHandlerRequest) { }
    func image(error _: ImageLoadingError, for _: URL) { }
}

/// No-op unread-count double - `removeReminder` never touches it.
@MainActor
private final class NoOpUnreadCountService: UnreadCountServiceType {
    var unreadCount: UnreadCount = .zero
    func refresh(accountKeychainId _: String) async { }
    func decrement(replies _: Int, mentions _: Int, privateMessages _: Int) { }
    func reset() { }
}

// MARK: - Tests

/// Covers the review-fix to `InboxViewModel.removeReminder`: the Inbox
/// Reminders segment now surfaces both `time` and `activity` reminders side
/// by side (Post Reminders Phase 2), and a post can carry one of each
/// independently - swiping to remove a row must cancel only the reminder OF
/// THAT ROW'S KIND. Before the fix, `removeReminder` unconditionally called
/// `removeTimeReminder`, which either no-op'd on an activity-only row or
/// destroyed a co-existing time reminder while leaving the activity follow in
/// place.
///
/// `ReminderService` is a concrete actor (not a protocol), so these tests
/// back `AccountScope.reminderService` with a REAL instance over an in-memory
/// `AppDatabase` rather than a call-recording spy, and assert on the
/// resulting rows.
@MainActor
struct InboxViewModelRemoveReminderTests {
    private let keychainId = "kc-inbox-remove-reminder-test"
    private static let postServerId: Int64 = 555
    private static let apId = "https://example.com/post/555"

    // MARK: - Fixture

    private struct Fixture {
        let viewModel: InboxViewModel
        let appDatabase: AppDatabase
        let accountId: Int64
    }

    /// Seeds an account row, then sets BOTH a `time` and an `activity`
    /// reminder on the same post - the exact "post with both a time reminder
    /// and an activity follow" scenario the bug report calls out.
    private func makeFixture() async throws -> Fixture {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://reminder-remove-test.example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return account.id!
        }

        let reminderService = ReminderService(
            accountId: accountId,
            appDatabase: appDatabase,
            scheduler: NoOpReminderScheduler()
        )
        try await reminderService.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            fireAt: Date(timeIntervalSince1970: 2_000_000_000),
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        try await reminderService.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            baselineCount: 3,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        let accountService = FakeRemoveReminderAccountService(reminderService: reminderService)
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        let viewModel = InboxViewModel(
            accountScope: scope,
            appDatabase: appDatabase,
            isSignedIn: true,
            myPersonId: nil,
            alertService: NoOpAlertService(),
            unreadCountService: NoOpUnreadCountService()
        )
        return Fixture(viewModel: viewModel, appDatabase: appDatabase, accountId: accountId)
    }

    /// Builds the `ReminderListRow` `removeReminder` would receive for a live
    /// row of `kind` on the fixture's seeded post - mirrors the shape
    /// `observeReminderList` emits, with placeholder values for the fields
    /// `removeReminder` doesn't read.
    private func row(kind: ReminderRecord.Kind) -> ReminderListRow {
        ReminderListRow(
            id: 1,
            postServerId: Self.postServerId,
            apId: Self.apId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: kind.rawValue,
            status: ReminderRecord.Status.scheduled.rawValue,
            unseen: false,
            fireAt: nil,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
    }

    /// `removeReminder` fires a detached `Task`, not an awaitable call - poll
    /// (bounded) until its write has landed rather than assuming a fixed
    /// delay is enough, mirroring the polling helpers in
    /// `InboxViewModelLoadMoreTests`.
    private func waitUntilRemoved(
        _ appDatabase: AppDatabase,
        accountId: Int64,
        kind: ReminderRecord.Kind
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if appDatabase.reminderSync(
                accountId: accountId,
                postServerId: Self.postServerId,
                rootCommentServerId: ReminderRecord.wholePostSentinel,
                kind: kind.rawValue
            ) == nil {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Tests

    /// Swiping an ACTIVITY row removes only the activity reminder; a
    /// co-existing time reminder on the same post survives.
    @Test
    func removeReminder_onActivityRow_removesOnlyActivityReminder() async throws {
        let fixture = try await makeFixture()

        fixture.viewModel.removeReminder(row(kind: .activity))
        await waitUntilRemoved(fixture.appDatabase, accountId: fixture.accountId, kind: .activity)

        let activityReminder = fixture.appDatabase.reminderSync(
            accountId: fixture.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(activityReminder == nil)

        let timeReminder = fixture.appDatabase.reminderSync(
            accountId: fixture.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        )
        #expect(timeReminder != nil)
    }

    /// Swiping a TIME row removes only the time reminder - the pre-existing
    /// (Phase 1) behavior, guarded here so the kind-aware switch doesn't
    /// invert the two branches.
    @Test
    func removeReminder_onTimeRow_removesOnlyTimeReminder() async throws {
        let fixture = try await makeFixture()

        fixture.viewModel.removeReminder(row(kind: .time))
        await waitUntilRemoved(fixture.appDatabase, accountId: fixture.accountId, kind: .time)

        let timeReminder = fixture.appDatabase.reminderSync(
            accountId: fixture.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        )
        #expect(timeReminder == nil)

        let activityReminder = fixture.appDatabase.reminderSync(
            accountId: fixture.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(activityReminder != nil)
    }
}

// MARK: - Trap helper

private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in InboxViewModelRemoveReminderTests")
}
