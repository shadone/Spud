//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class PostInteractionUpdateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_500)

    private func snapshot(_ title: String) -> PostInteractionSnapshot {
        PostInteractionSnapshot(
            titleSnapshot: title,
            communityName: "tech",
            instanceHost: "lemmy.world",
            thumbnailUrl: nil,
            author: "alice"
        )
    }

    // MARK: applyingOpen

    func testFirstOpenCreatesRowWithNilPrevious() {
        let (record, previous) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: snapshot("Hello")
        )
        XCTAssertNil(previous)
        XCTAssertEqual(record.lastOpenedAt, t0)
        XCTAssertEqual(record.openedCount, 1)
        XCTAssertEqual(record.lastKnownCommentCount, 12)
        XCTAssertEqual(record.titleSnapshot, "Hello")
        XCTAssertEqual(record.seenCount, 0)
        XCTAssertNil(record.firstSeenAt)
    }

    func testSecondOpenReturnsPriorTimestampAndBumpsCount() {
        let (first, _) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: snapshot("Hello")
        )
        let (second, previous) = PostInteractionUpdate.applyingOpen(
            to: first, accountId: 1, postServerId: 9, now: t1,
            commentCount: 15, snapshot: nil
        )
        XCTAssertEqual(previous, t0)
        XCTAssertEqual(second.lastOpenedAt, t1)
        XCTAssertEqual(second.openedCount, 2)
        XCTAssertEqual(second.lastKnownCommentCount, 15)
        // nil snapshot keeps the prior snapshot
        XCTAssertEqual(second.titleSnapshot, "Hello")
    }

    func testOpenWithNilCommentCountKeepsPriorCount() {
        let (first, _) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: nil
        )
        let (second, _) = PostInteractionUpdate.applyingOpen(
            to: first, accountId: 1, postServerId: 9, now: t1,
            commentCount: nil, snapshot: nil
        )
        XCTAssertEqual(second.lastKnownCommentCount, 12)
    }

    // MARK: applyingSeen

    func testFirstSeenSetsBothTimestamps() {
        let record = PostInteractionUpdate.applyingSeen(
            to: nil, accountId: 1, postServerId: 9, now: t0, snapshot: snapshot("Hi")
        )
        XCTAssertEqual(record.firstSeenAt, t0)
        XCTAssertEqual(record.lastSeenAt, t0)
        XCTAssertEqual(record.seenCount, 1)
        XCTAssertEqual(record.openedCount, 0)
    }

    func testSecondSeenKeepsFirstSeenBumpsLast() {
        let first = PostInteractionUpdate.applyingSeen(
            to: nil, accountId: 1, postServerId: 9, now: t0, snapshot: snapshot("Hi")
        )
        let second = PostInteractionUpdate.applyingSeen(
            to: first, accountId: 1, postServerId: 9, now: t1, snapshot: snapshot("Hi")
        )
        XCTAssertEqual(second.firstSeenAt, t0)
        XCTAssertEqual(second.lastSeenAt, t1)
        XCTAssertEqual(second.seenCount, 2)
    }

    // MARK: shouldPrune

    func testSavedPostIsNeverPruned() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = Date(timeIntervalSince1970: 0) // ancient
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0, isSaved: true,
            seenRetention: 1, openedRetention: 1
        )
        XCTAssertFalse(prune)
    }

    func testOldSeenOnlyIsPruned() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(40 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        XCTAssertTrue(prune)
    }

    func testRecentSeenOnlyIsKept() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(10 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        XCTAssertFalse(prune)
    }

    func testOpenedUsesOpenedRetentionNotSeen() {
        // Opened 40 days ago: beyond the 30-day seen window but inside the
        // 1-year opened window, so it must be kept.
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastOpenedAt = t0
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(40 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        XCTAssertFalse(prune)
    }

    func testRecordWithNoTimestampIsNotPruned() {
        let record = PostInteractionRecord(accountId: 1, postServerId: 9)
        XCTAssertFalse(PostInteractionUpdate.shouldPrune(
            record, now: t0, isSaved: false,
            seenRetention: 1, openedRetention: 1
        ))
    }
}
