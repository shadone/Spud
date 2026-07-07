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
    override func setUp() {
        super.setUp()
        // Pin the process-wide accent so renders don't depend on the sim's
        // persisted accent preference. See `SnapshotDeterminism.pinAccent()`.
        SnapshotDeterminism.pinAccent()
        // Pin the host scene's status bar hidden so nav-hosted / key-window
        // captures are immune to the sim's persisted orientation state (the
        // 44pt-shift regression). See
        // `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

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

    // MARK: - Seeded content

    private let seededTitle = "Local Harvest Festival — anyone going?"
    private let seededBody = "Looking forward to the harvest festival this year. Anyone else going?"

    // MARK: - Render detection

    /// Recursively walks `view` and returns true if any visible `UILabel`'s text
    /// contains `text`. Used to confirm the GRDB observation delivered the seeded
    /// row and the VC actually rendered it before we snapshot.
    private func hierarchyContainsLabel(_ view: UIView, text: String) -> Bool {
        if let label = view as? UILabel, label.isHidden == false, label.text?.contains(text) == true {
            return true
        }
        for subview in view.subviews where hierarchyContainsLabel(subview, text: text) {
            return true
        }
        return false
    }

    /// True once the failed banner control (the Retry button) is visible.
    private func hierarchyContainsVisibleRetry(_ view: UIView) -> Bool {
        if let button = view as? UIButton,
           button.isHidden == false,
           button.configuration?.title == "Retry"
        {
            return true
        }
        for subview in view.subviews where hierarchyContainsVisibleRetry(subview) {
            return true
        }
        return false
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
                body: seededBody,
                postServerId: nil,
                parentCommentServerId: nil,
                communityServerId: 42,
                title: seededTitle,
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

            // Wait deterministically for the async GRDB observation to deliver the
            // seeded row and the VC to render it. We must genuinely SUSPEND the
            // MainActor (Task.sleep) rather than spin the run loop synchronously —
            // the observation lands on a `Task { @MainActor }` continuation that
            // can only run while this method is suspended. Poll up to ~3s for the
            // seeded title to appear, plus (for the failed state) the Retry button.
            let deadline = Date().addingTimeInterval(3)
            var rendered = false
            while Date() < deadline {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 50_000_000)
                navigationController.view.layoutIfNeeded()

                let hasTitle = hierarchyContainsLabel(vc.view, text: seededTitle)
                let bannerReady = status == .failed
                    ? hierarchyContainsVisibleRetry(vc.view)
                    : true
                if hasTitle, bannerReady {
                    rendered = true
                    break
                }
            }

            guard rendered else {
                XCTFail(
                    """
                    PendingPostViewController never rendered the seeded post for status \(status). \
                    Title visible: \(hierarchyContainsLabel(vc.view, text: seededTitle)), \
                    Retry visible: \(hierarchyContainsVisibleRetry(vc.view)). \
                    Refusing to snapshot a blank/default screen.
                    """,
                    line: line
                )
                return
            }

            // Final settle so the markdown body Task delivers its blocks and the
            // layout is stable before capture.
            try? await Task.sleep(nanoseconds: 200_000_000)
            navigationController.view.layoutIfNeeded()

            let size = CGSize(width: 390, height: 844)
            assertSnapshot(
                matching: navigationController,
                as: .image(
                    on: .deterministicPhone,
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
