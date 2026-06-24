//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class LinkURLTests: XCTestCase {
    private let home = "https://discuss.tchncs.de"
    private let apId = "https://lemmy.world/post/123"
    private let commentApId = "https://lemmy.world/comment/99"

    // MARK: forPost

    func test_post_originalInstance_usesApId() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://lemmy.world/post/123")
    }

    func test_post_myInstance_ignoresApIdAndUsesHome() {
        let url = LinkURL.forPost(
            instance: .myInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/post/5")
    }

    func test_post_originalInstance_missingApId_fallsBackToHome() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: nil,
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/post/5")
    }

    func test_post_originalInstance_emptyApId_fallsBackToHome() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: "",
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/post/5")
    }

    func test_post_myInstance_noInstanceActorId_returnsNil() {
        let url = LinkURL.forPost(
            instance: .myInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: nil
        )
        XCTAssertNil(url)
    }

    func test_post_originalInstance_noApIdNoInstance_returnsNil() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: nil,
            serverPostId: 5,
            instanceActorId: nil
        )
        XCTAssertNil(url)
    }

    // MARK: forComment

    func test_comment_originalInstance_usesApId() {
        let url = LinkURL.forComment(
            instance: .originalInstance,
            originalCommentUrl: commentApId,
            serverCommentId: 7,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://lemmy.world/comment/99")
    }

    func test_comment_myInstance_usesHome() {
        let url = LinkURL.forComment(
            instance: .myInstance,
            originalCommentUrl: commentApId,
            serverCommentId: 7,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/comment/7")
    }
}
