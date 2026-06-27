//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PostInteractionUpdateTests {
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

    @Test
    func firstOpenCreatesRowWithNilPrevious() {
        let (record, previous) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: snapshot("Hello")
        )
        #expect(previous == nil)
        #expect(record.lastOpenedAt == t0)
        #expect(record.openedCount == 1)
        #expect(record.lastKnownCommentCount == 12)
        #expect(record.titleSnapshot == "Hello")
        #expect(record.seenCount == 0)
        #expect(record.firstSeenAt == nil)
    }

    @Test
    func secondOpenReturnsPriorTimestampAndBumpsCount() {
        let (first, _) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: snapshot("Hello")
        )
        let (second, previous) = PostInteractionUpdate.applyingOpen(
            to: first, accountId: 1, postServerId: 9, now: t1,
            commentCount: 15, snapshot: nil
        )
        #expect(previous == t0)
        #expect(second.lastOpenedAt == t1)
        #expect(second.openedCount == 2)
        #expect(second.lastKnownCommentCount == 15)
        // nil snapshot keeps the prior snapshot
        #expect(second.titleSnapshot == "Hello")
    }

    @Test
    func openWithNilCommentCountKeepsPriorCount() {
        let (first, _) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: nil
        )
        let (second, _) = PostInteractionUpdate.applyingOpen(
            to: first, accountId: 1, postServerId: 9, now: t1,
            commentCount: nil, snapshot: nil
        )
        #expect(second.lastKnownCommentCount == 12)
    }

    // MARK: applyingSeen

    @Test
    func firstSeenSetsBothTimestamps() {
        let record = PostInteractionUpdate.applyingSeen(
            to: nil, accountId: 1, postServerId: 9, now: t0, snapshot: snapshot("Hi")
        )
        #expect(record.firstSeenAt == t0)
        #expect(record.lastSeenAt == t0)
        #expect(record.seenCount == 1)
        #expect(record.openedCount == 0)
    }

    @Test
    func secondSeenKeepsFirstSeenBumpsLast() {
        let first = PostInteractionUpdate.applyingSeen(
            to: nil, accountId: 1, postServerId: 9, now: t0, snapshot: snapshot("Hi")
        )
        let second = PostInteractionUpdate.applyingSeen(
            to: first, accountId: 1, postServerId: 9, now: t1, snapshot: snapshot("Hi")
        )
        #expect(second.firstSeenAt == t0)
        #expect(second.lastSeenAt == t1)
        #expect(second.seenCount == 2)
    }

    // MARK: shouldPrune

    @Test
    func savedPostIsNeverPruned() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = Date(timeIntervalSince1970: 0) // ancient
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0, isSaved: true,
            seenRetention: 1, openedRetention: 1
        )
        #expect(!prune)
    }

    @Test
    func oldSeenOnlyIsPruned() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(40 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        #expect(prune)
    }

    @Test
    func recentSeenOnlyIsKept() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(10 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        #expect(!prune)
    }

    @Test
    func openedUsesOpenedRetentionNotSeen() {
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
        #expect(!prune)
    }

    @Test
    func recordWithNoTimestampIsNotPruned() {
        let record = PostInteractionRecord(accountId: 1, postServerId: 9)
        #expect(!(PostInteractionUpdate.shouldPrune(
            record, now: t0, isSaved: false,
            seenRetention: 1, openedRetention: 1
        )))
    }
}
