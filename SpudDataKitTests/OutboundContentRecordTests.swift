//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct OutboundContentRecordTests {
    @Test
    func commentDraftKey_topLevel_usesZeroForParent() {
        #expect(OutboundContentRecord.commentDraftKey(postServerId: 42, parentCommentServerId: nil) == "c:42:0")
    }

    @Test
    func commentDraftKey_reply_includesParent() {
        #expect(OutboundContentRecord.commentDraftKey(postServerId: 42, parentCommentServerId: 99) == "c:42:99")
    }

    @Test
    func postDraftKey_noCommunity_usesZero() {
        #expect(OutboundContentRecord.postDraftKey(communityServerId: nil) == "p:0")
    }

    @Test
    func draftKey_dispatchesOnKind() {
        let comment = OutboundDraftInput(
            kind: .comment,
            body: "hi",
            postServerId: 7,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0
        )
        let post = OutboundDraftInput(
            kind: .post,
            body: "",
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: 3,
            title: "T",
            url: nil,
            nsfw: false,
            postType: 0
        )
        #expect(OutboundContentRecord.draftKey(for: comment) == "c:7:0")
        #expect(OutboundContentRecord.draftKey(for: post) == "p:3")
    }
}
