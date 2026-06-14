//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import XCTest
@testable import SpudDataKit

private typealias Person = Components.Schemas.Person
private typealias Community = Components.Schemas.Community
private typealias Post = Components.Schemas.Post
private typealias Comment = Components.Schemas.Comment
private typealias CommentView = Components.Schemas.CommentView
private typealias ModRemoveCommentView = Components.Schemas.ModRemoveCommentView

/// Covers the modlog removal-reason service path: correlating modlog entries
/// into a `commentId -> reason` map, and mirroring those reasons onto comments.
final class CommentRemovalReasonTests: XCTestCase {
    // MARK: Correlation

    /// Builds a modlog comment-removal entry. Only `mod_remove_comment` matters
    /// to the correlation; the rest is filler so the view type is satisfied.
    private func entry(commentId: Components.Schemas.CommentID, reason: String?, removed: Bool) -> ModRemoveCommentView {
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        let comment = Comment.fake(id: commentId, post: post, creator: person, parent: .root)
        return .init(
            mod_remove_comment: .init(
                id: 1,
                mod_person_id: person.id,
                comment_id: commentId,
                reason: reason,
                removed: removed,
                when_: Date(timeIntervalSince1970: 0)
            ),
            moderator: person,
            comment: comment,
            commenter: person,
            post: post,
            community: community
        )
    }

    func testRemovalReasonsKeepsNewestAndSkipsRestoresAndEmpty() {
        let views: [ModRemoveCommentView] = [
            // Newest-first: comment 10 was removed twice — the first (most
            // recent) reason must win.
            entry(commentId: 10, reason: "current reason", removed: true),
            entry(commentId: 10, reason: "stale reason", removed: true),
            entry(commentId: 20, reason: nil, removed: true), // no reason -> skip
            entry(commentId: 21, reason: "", removed: true), // empty reason -> skip
            entry(commentId: 22, reason: "was restored", removed: false), // restored -> skip
            entry(commentId: 30, reason: "spam", removed: true),
        ]

        let reasons = LemmyService.removalReasons(from: views)

        XCTAssertEqual(reasons[10], "current reason")
        XCTAssertNil(reasons[20])
        XCTAssertNil(reasons[21])
        XCTAssertNil(reasons[22])
        XCTAssertEqual(reasons[30], "spam")
        XCTAssertEqual(reasons.count, 2)
    }

    func testRemovalReasonsEmptyInput() {
        XCTAssertTrue(LemmyService.removalReasons(from: []).isEmpty)
    }

    // MARK: Mirroring

    func testMirrorCommentRemovalReasonsUpdatesMatchingComment() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let serverPostId: Int64 = 1
        let serverCommentId: Components.Schemas.CommentID = 42

        // Seed account + site + post so a comment can attach.
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-1",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }

        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        _ = try await appDatabase.upsertPost(
            from: .fake(post: post, creator: person, community: community),
            accountId: accountId,
            siteId: siteId
        )
        let commentView = CommentView.fake(
            comment: .fake(id: serverCommentId, post: post, creator: person, parent: .root),
            creator: person,
            post: post,
            community: community,
            childCount: 0
        )
        try await appDatabase.upsertComments(
            forServerPostId: serverPostId,
            accountId: accountId,
            siteId: siteId,
            sortType: .Hot,
            comments: [commentView]
        )

        try await appDatabase.mirrorCommentRemovalReasons(
            forServerPostId: serverPostId,
            accountId: accountId,
            reasonsByServerCommentId: [Int64(serverCommentId): "rule 2 · be civil"]
        )

        let storedReason = try await appDatabase.writer.read { db -> String? in
            try CommentRecord
                .filter(Column("localCommentId") == Int64(serverCommentId))
                .fetchOne(db)?
                .removedReason
        }
        XCTAssertEqual(storedReason, "rule 2 · be civil")
    }
}
