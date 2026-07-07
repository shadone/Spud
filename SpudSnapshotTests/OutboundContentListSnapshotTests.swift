//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Screen snapshots of `OutboundContentListViewController` populated with one
/// failed row, one sending row, and one draft row, in light and dark.
///
/// The in-memory database is seeded before the VC is created. The GRDB
/// observation delivers its first value asynchronously, so we poll with
/// genuine `await Task.sleep` suspensions until all three rows appear in the
/// hierarchy before snapshotting. A fixed sleep is NOT used — the test
/// XCTFails if content does not appear within the deadline.
@MainActor
final class OutboundContentListSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Pin the process-wide accent so renders don't depend on the sim's
        // persisted accent preference. See `SnapshotDeterminism.pinAccent()`.
        SnapshotDeterminism.pinAccent()
        // Pin the host scene's status bar hidden so nav-hosted / key-window
        // captures are immune to an active Simulator GUI session. See
        // `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    struct SnapshotDependencies: HasImageService, HasAccountService, HasAppDatabase {
        let imageService: ImageServiceType
        let accountService: AccountServiceType
        let appDatabase: AppDatabase
    }

    // MARK: - Seed helpers

    private func makeDependencies() throws -> SnapshotDependencies {
        let appDatabase = try AppDatabase.inMemory()
        return SnapshotDependencies(
            imageService: StaticImageService(),
            accountService: AccountService(appDatabase: appDatabase),
            appDatabase: appDatabase
        )
    }

    /// Seeds a minimal account and returns (accountId, accountKeychainId).
    private func seedAccount(_ appDatabase: AppDatabase) async throws -> (Int64, String) {
        let keychainId = "outbox-snapshot@seed.test"
        let accountId = try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://seed.test', ?)",
                arguments: [Date()]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, Date(), Date()]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                    VALUES (?, ?, 0, 0, 0, ?, ?)
                    """,
                arguments: [siteId, keychainId, Date(), Date()]
            )
            return db.lastInsertedRowID
        }
        return (accountId, keychainId)
    }

    // MARK: - Render detection

    /// Recursively walks `view` and returns true if any visible `UILabel`'s text
    /// contains `text`.
    private func hierarchyContainsLabel(_ view: UIView, text: String) -> Bool {
        if let label = view as? UILabel,
           label.isHidden == false,
           label.text?.contains(text) == true
        {
            return true
        }
        for subview in view.subviews where hierarchyContainsLabel(subview, text: text) {
            return true
        }
        return false
    }

    // MARK: - Snapshot helper

    func test_allSections() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try makeDependencies()
            let (accountId, keychainId) = try await seedAccount(dependencies.appDatabase)

            let now = Date().timeIntervalSince1970

            // Insert a FAILED post.
            let failedInput = OutboundDraftInput(
                kind: .post,
                body: "This post failed to send.",
                postServerId: nil,
                parentCommentServerId: nil,
                communityServerId: 1,
                title: "My Failed Post",
                url: nil,
                nsfw: false,
                postType: 0
            )
            let failedToken = try await dependencies.appDatabase.upsertOutboundDraft(
                failedInput,
                accountId: accountId,
                now: now - 200
            )
            let failedRowIdValue = try await dependencies.appDatabase.writer.read { db in
                try Int64.fetchOne(
                    db,
                    sql: "SELECT id FROM outboundContent WHERE clientToken = ?",
                    arguments: [failedToken]
                )
            }
            let failedRowId = try XCTUnwrap(failedRowIdValue)
            try await dependencies.appDatabase.markOutboundFailed(
                id: failedRowId,
                lastError: "Server returned 500",
                now: now - 200
            )

            // Insert a SENDING comment.
            let sendingInput = OutboundDraftInput(
                kind: .comment,
                body: "This comment is being sent right now.",
                postServerId: 42,
                parentCommentServerId: nil,
                communityServerId: nil,
                title: nil,
                url: nil,
                nsfw: false,
                postType: 0
            )
            let sendingToken = try await dependencies.appDatabase.upsertOutboundDraft(
                sendingInput,
                accountId: accountId,
                now: now - 100
            )
            try await dependencies.appDatabase.markOutboundQueued(clientToken: sendingToken, now: now - 100)

            // Insert a DRAFT comment.
            let draftInput = OutboundDraftInput(
                kind: .comment,
                body: "This is a saved draft comment I haven't sent yet.",
                postServerId: 99,
                parentCommentServerId: nil,
                communityServerId: nil,
                title: nil,
                url: nil,
                nsfw: false,
                postType: 0
            )
            _ = try await dependencies.appDatabase.upsertOutboundDraft(
                draftInput,
                accountId: accountId,
                now: now
            )

            let vc = OutboundContentListViewController(
                accountKeychainId: keychainId,
                dependencies: dependencies
            )
            let nav = UINavigationController(rootViewController: vc)

            nav.loadViewIfNeeded()
            nav.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            nav.view.layoutIfNeeded()

            // Poll deterministically: wait for all three representative strings to
            // appear in the view hierarchy. The GRDB observation delivers on a
            // background Task continuation that only runs while this coroutine is
            // suspended — a fixed sleep is not sufficient; we must await.
            let deadline = Date().addingTimeInterval(3)
            var rendered = false
            while Date() < deadline {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 50_000_000)
                nav.view.layoutIfNeeded()

                let hasFailedRow = hierarchyContainsLabel(vc.view, text: "My Failed Post")
                let hasSendingRow = hierarchyContainsLabel(vc.view, text: "This comment is being sent right now.")
                let hasDraftRow = hierarchyContainsLabel(vc.view, text: "This is a saved draft comment I haven't sent yet.")

                if hasFailedRow, hasSendingRow, hasDraftRow {
                    rendered = true
                    break
                }
            }

            guard rendered else {
                let hasFailedRow = hierarchyContainsLabel(vc.view, text: "My Failed Post")
                let hasSendingRow = hierarchyContainsLabel(vc.view, text: "This comment is being sent right now.")
                let hasDraftRow = hierarchyContainsLabel(vc.view, text: "This is a saved draft comment I haven't sent yet.")
                XCTFail(
                    """
                    OutboundContentListViewController never rendered all three seeded rows. \
                    Failed visible: \(hasFailedRow), \
                    Sending visible: \(hasSendingRow), \
                    Draft visible: \(hasDraftRow). \
                    Refusing to snapshot a blank/under-rendered screen.
                    """
                )
                return
            }

            // Final settle for layout stability.
            try? await Task.sleep(nanoseconds: 200_000_000)
            nav.view.layoutIfNeeded()

            let size = CGSize(width: 390, height: 844)
            assertSnapshot(
                matching: nav,
                as: .image(
                    on: .deterministicPhone,
                    size: size,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light",
                testName: #function
            )
        }
    }
}
