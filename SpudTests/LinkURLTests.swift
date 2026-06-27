//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct LinkURLTests {
    private let home = "https://discuss.tchncs.de"
    private let apId = "https://lemmy.world/post/123"
    private let commentApId = "https://lemmy.world/comment/99"

    // MARK: forPost

    @Test
    func post_originalInstance_usesApId() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://lemmy.world/post/123")
    }

    @Test
    func post_myInstance_ignoresApIdAndUsesHome() {
        let url = LinkURL.forPost(
            instance: .myInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://discuss.tchncs.de/post/5")
    }

    @Test
    func post_originalInstance_missingApId_fallsBackToHome() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: nil,
            serverPostId: 5,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://discuss.tchncs.de/post/5")
    }

    @Test
    func post_originalInstance_emptyApId_fallsBackToHome() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: "",
            serverPostId: 5,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://discuss.tchncs.de/post/5")
    }

    @Test
    func post_myInstance_noInstanceActorId_returnsNil() {
        let url = LinkURL.forPost(
            instance: .myInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: nil
        )
        #expect(url == nil)
    }

    @Test
    func post_originalInstance_noApIdNoInstance_returnsNil() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: nil,
            serverPostId: 5,
            instanceActorId: nil
        )
        #expect(url == nil)
    }

    // MARK: forComment

    @Test
    func comment_originalInstance_usesApId() {
        let url = LinkURL.forComment(
            instance: .originalInstance,
            originalCommentUrl: commentApId,
            serverCommentId: 7,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://lemmy.world/comment/99")
    }

    @Test
    func comment_myInstance_usesHome() {
        let url = LinkURL.forComment(
            instance: .myInstance,
            originalCommentUrl: commentApId,
            serverCommentId: 7,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://discuss.tchncs.de/comment/7")
    }

    @Test
    func comment_originalInstance_missingApId_fallsBackToHome() {
        let url = LinkURL.forComment(
            instance: .originalInstance,
            originalCommentUrl: nil,
            serverCommentId: 7,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://discuss.tchncs.de/comment/7")
    }

    @Test
    func comment_originalInstance_emptyApId_fallsBackToHome() {
        let url = LinkURL.forComment(
            instance: .originalInstance,
            originalCommentUrl: "",
            serverCommentId: 7,
            instanceActorId: home
        )
        #expect(url?.absoluteString == "https://discuss.tchncs.de/comment/7")
    }

    @Test
    func comment_myInstance_noInstanceActorId_returnsNil() {
        let url = LinkURL.forComment(
            instance: .myInstance,
            originalCommentUrl: commentApId,
            serverCommentId: 7,
            instanceActorId: nil
        )
        #expect(url == nil)
    }

    @Test
    func comment_originalInstance_noApIdNoInstance_returnsNil() {
        let url = LinkURL.forComment(
            instance: .originalInstance,
            originalCommentUrl: nil,
            serverCommentId: 7,
            instanceActorId: nil
        )
        #expect(url == nil)
    }
}
