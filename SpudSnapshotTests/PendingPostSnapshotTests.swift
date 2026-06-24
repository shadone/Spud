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

/// Screen snapshots of `PendingPostViewController` in its two terminal states
/// (sending / failed) in light and dark. The in-memory database is seeded with
/// one outbound post row before the VC is created so the AsyncStream observation
/// delivers the row before the snapshot is taken.
@MainActor
final class PendingPostSnapshotTests: XCTestCase {
    struct SnapshotDependencies: HasImageService, HasAccountService, HasAppDatabase {
        let imageService: ImageServiceType
        let accountService: AccountServiceType
        let appDatabase: AppDatabase
    }

    // MARK: - Seed helpers

    /// Inserts a minimal account row and returns (accountId, accountKeychainId).
    private func seedAccount(_ appDatabase: AppDatabase) async throws -> (Int64, String) {
        let keychainId = "snapshot@seed.test"
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

    private func makeDependencies() throws -> SnapshotDependencies {
        let appDatabase = try AppDatabase.inMemory()
        return SnapshotDependencies(
            imageService: StaticImageService(),
            accountService: AccountService(appDatabase: appDatabase),
            appDatabase: appDatabase
        )
    }

    // MARK: - Snapshot helper

    private func assertScreens(
        status: OutboundStatus,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try makeDependencies()
            let (accountId, keychainId) = try await seedAccount(dependencies.appDatabase)

            // Insert the draft row.
            let input = OutboundDraftInput(
                kind: .post,
                body: "Looking forward to the harvest festival this year. Anyone else going?",
                postServerId: nil,
                parentCommentServerId: nil,
                communityServerId: 42,
                title: "Local Harvest Festival — anyone going?",
                url: nil,
                nsfw: false,
                postType: 0
            )
            let now = Date().timeIntervalSince1970
            let clientToken = try await dependencies.appDatabase.upsertOutboundDraft(
                input,
                accountId: accountId,
                now: now
            )

            // Transition to the desired status.
            switch status {
            case .draft:
                break
            case .queued:
                try await dependencies.appDatabase.markOutboundQueued(clientToken: clientToken, now: now)
            case .sending:
                // markOutboundSending requires the row id; read it first.
                let rowId = try await dependencies.appDatabase.writer.read { db in
                    try Int64.fetchOne(
                        db,
                        sql: "SELECT id FROM outboundContent WHERE clientToken = ?",
                        arguments: [clientToken]
                    )
                }!
                try await dependencies.appDatabase.markOutboundSending(id: rowId, now: now)
            case .failed:
                let rowId = try await dependencies.appDatabase.writer.read { db in
                    try Int64.fetchOne(
                        db,
                        sql: "SELECT id FROM outboundContent WHERE clientToken = ?",
                        arguments: [clientToken]
                    )
                }!
                try await dependencies.appDatabase.markOutboundFailed(
                    id: rowId,
                    lastError: "Server returned 500",
                    now: now
                )
            }

            let vc = PendingPostViewController(
                clientToken: clientToken,
                accountKeychainId: keychainId,
                dependencies: dependencies
            )
            let navigationController = UINavigationController(rootViewController: vc)

            // Force layout so the view loads and startObservations() runs.
            navigationController.loadViewIfNeeded()
            navigationController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            navigationController.view.layoutIfNeeded()

            // Spin the run loop so the async GRDB observation delivers the first value.
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                // Check whether the title label has content — that means the row landed.
                if vc.view.subviews.first != nil { break }
            }
            // Extra settle pass so the markdown body Task can also deliver.
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            navigationController.view.layoutIfNeeded()

            let size = CGSize(width: 390, height: 844)
            assertSnapshot(
                matching: navigationController,
                as: .image(
                    on: .iPhone13Pro,
                    size: size,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    // MARK: - States

    func test_sending() async throws {
        try await assertScreens(status: .sending)
    }

    func test_failed() async throws {
        try await assertScreens(status: .failed)
    }
}
