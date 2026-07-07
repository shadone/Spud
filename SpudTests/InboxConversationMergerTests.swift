//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import Spud
@testable import SpudDataKit

/// Unit coverage for the inbox conversation-list merge: confirmed conversations
/// from `observeConversations` combined with the account's still-pending
/// outbound DMs into the render-ready `[InboxConversation]`.
///
/// Pure function, no DB — the view-model supplies the live data and a recipient
/// resolver, both stubbed here.
struct InboxConversationMergerTests {
    // MARK: - Fixtures

    private enum PID {
        static let alice: Int64 = 200
        static let bob: Int64 = 300
        static let carol: Int64 = 400
    }

    private static func conversationRow(
        correspondent: Int64,
        name: String?,
        avatar: String? = nil,
        latestContent: String,
        latestPublished: TimeInterval,
        unreadCount: Int = 0
    ) -> PrivateMessageConversationRow {
        PrivateMessageConversationRow(
            correspondentServerPersonId: correspondent,
            correspondentName: name,
            correspondentAvatarUrl: avatar,
            latestContent: latestContent,
            latestPublished: Date(timeIntervalSince1970: latestPublished),
            unreadCount: unreadCount
        )
    }

    private static func outboundDM(
        recipient: Int64?,
        body: String,
        status: OutboundStatus,
        createdAt: TimeInterval,
        clientToken: String = UUID().uuidString
    ) -> OutboundContentRecord {
        OutboundContentRecord(
            id: nil,
            clientToken: clientToken,
            accountId: 1,
            kind: OutboundKind.directMessage.rawValue,
            status: status.rawValue,
            draftKey: "dm:\(recipient ?? 0):send:\(clientToken)",
            body: body,
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0,
            editCommentServerId: nil,
            editPostServerId: nil,
            recipientServerPersonId: recipient,
            attempts: 0,
            lastError: nil,
            nextAttemptAt: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    /// Resolver that knows every fixture correspondent by name; returns nil for
    /// anyone else (exercising the unknown-name fallback).
    private static func resolver(_ id: Int64) -> InboxConversationMerger.CorrespondentInfo {
        switch id {
        case PID.alice: .init(name: "Alice", avatarUrl: nil)
        case PID.bob: .init(name: "Bob", avatarUrl: nil)
        case PID.carol: .init(name: "Carol", avatarUrl: nil)
        default: .init(name: nil, avatarUrl: nil)
        }
    }

    // MARK: - No pending

    @Test
    func confirmedOnly_passesThroughNewestFirst() {
        let merged = InboxConversationMerger.merge(
            conversations: [
                Self.conversationRow(correspondent: PID.alice, name: "Alice", latestContent: "hi alice", latestPublished: 1200),
                Self.conversationRow(correspondent: PID.bob, name: "Bob", latestContent: "hi bob", latestPublished: 900),
            ],
            outboundDMs: [],
            resolveCorrespondent: Self.resolver
        )

        #expect(merged.map(\.correspondentId) == [Lemmy.PersonID(PID.alice), Lemmy.PersonID(PID.bob)])
        #expect(merged.allSatisfy { $0.pendingStatus == nil })
    }

    // MARK: - Pending indicator on an existing conversation

    @Test
    func pendingSend_decoratesExistingConversation() throws {
        let merged = InboxConversationMerger.merge(
            conversations: [
                Self.conversationRow(correspondent: PID.alice, name: "Alice", latestContent: "earlier", latestPublished: 1000),
            ],
            outboundDMs: [
                Self.outboundDM(recipient: PID.alice, body: "sending now", status: .sending, createdAt: 1100),
            ],
            resolveCorrespondent: Self.resolver
        )

        let alice = try #require(merged.first)
        #expect(alice.pendingStatus == .sending)
        // The newer outbound body previews over the older confirmed message.
        #expect(alice.latestContent == "sending now")
        #expect(alice.latestPublished == Date(timeIntervalSince1970: 1100))
    }

    @Test
    func failedDominatesSending_onSameConversation() {
        let merged = InboxConversationMerger.merge(
            conversations: [
                Self.conversationRow(correspondent: PID.alice, name: "Alice", latestContent: "earlier", latestPublished: 1000),
            ],
            outboundDMs: [
                Self.outboundDM(recipient: PID.alice, body: "queued", status: .sending, createdAt: 1100),
                Self.outboundDM(recipient: PID.alice, body: "bad one", status: .failed, createdAt: 1050),
            ],
            resolveCorrespondent: Self.resolver
        )

        #expect(merged.first?.pendingStatus == .failed)
    }

    @Test
    func olderPending_doesNotOverridePreviewOfNewerConfirmed() throws {
        let merged = InboxConversationMerger.merge(
            conversations: [
                Self.conversationRow(correspondent: PID.alice, name: "Alice", latestContent: "newest confirmed", latestPublished: 2000),
            ],
            outboundDMs: [
                Self.outboundDM(recipient: PID.alice, body: "stale send", status: .sending, createdAt: 1500),
            ],
            resolveCorrespondent: Self.resolver
        )

        let alice = try #require(merged.first)
        // Still flagged sending, but the confirmed message is newer so it stays the preview.
        #expect(alice.pendingStatus == .sending)
        #expect(alice.latestContent == "newest confirmed")
    }

    // MARK: - Synthetic pending-only conversation

    @Test
    func pendingOnly_appearsAsSyntheticConversation() throws {
        let merged = InboxConversationMerger.merge(
            conversations: [],
            outboundDMs: [
                Self.outboundDM(recipient: PID.carol, body: "first message", status: .sending, createdAt: 1300),
            ],
            resolveCorrespondent: Self.resolver
        )

        #expect(merged.count == 1)
        let carol = try #require(merged.first)
        #expect(carol.correspondentId == Lemmy.PersonID(PID.carol))
        #expect(carol.correspondentName == "Carol")
        #expect(carol.latestContent == "first message")
        #expect(carol.pendingStatus == .sending)
        #expect(carol.unreadCount == 0)
    }

    @Test
    func pendingOnly_unknownRecipient_fallsBackToNeutralName() throws {
        let unknown: Int64 = 999
        let merged = InboxConversationMerger.merge(
            conversations: [],
            outboundDMs: [
                Self.outboundDM(recipient: unknown, body: "hello?", status: .sending, createdAt: 1000),
            ],
            resolveCorrespondent: Self.resolver
        )

        let row = try #require(merged.first)
        #expect(row.correspondentName == "Unknown")
    }

    @Test
    func malformedOutbound_withNilRecipient_isSkipped() {
        let merged = InboxConversationMerger.merge(
            conversations: [],
            outboundDMs: [
                Self.outboundDM(recipient: nil, body: "orphan", status: .sending, createdAt: 1000),
            ],
            resolveCorrespondent: Self.resolver
        )

        #expect(merged.isEmpty)
    }

    // MARK: - Collapse by correspondent id

    @Test
    func syntheticCollapsesIntoConfirmed_byCorrespondentId() throws {
        // Same recipient (Alice) has BOTH a confirmed conversation and an outbound
        // send: the merge must produce ONE row (the confirmed thread, decorated),
        // never a duplicate synthetic row.
        let merged = InboxConversationMerger.merge(
            conversations: [
                Self.conversationRow(correspondent: PID.alice, name: "Alice", latestContent: "history", latestPublished: 1000),
            ],
            outboundDMs: [
                Self.outboundDM(recipient: PID.alice, body: "still sending", status: .sending, createdAt: 1100),
            ],
            resolveCorrespondent: Self.resolver
        )

        #expect(merged.count == 1)
        let alice = try #require(merged.first)
        #expect(alice.correspondentId == Lemmy.PersonID(PID.alice))
        #expect(alice.pendingStatus == .sending)
    }

    @Test
    func confirmedAndSynthetic_orderByLatestTimestamp() {
        // Bob has an old confirmed thread; Carol is a brand-new pending-only send
        // that is more recent — Carol must sort first.
        let merged = InboxConversationMerger.merge(
            conversations: [
                Self.conversationRow(correspondent: PID.bob, name: "Bob", latestContent: "old", latestPublished: 500),
            ],
            outboundDMs: [
                Self.outboundDM(recipient: PID.carol, body: "brand new", status: .sending, createdAt: 1500),
            ],
            resolveCorrespondent: Self.resolver
        )

        #expect(merged.map(\.correspondentId) == [
            Lemmy.PersonID(PID.carol),
            Lemmy.PersonID(PID.bob),
        ])
    }

    @Test
    func equalTimestamp_tieBreaksByHigherCorrespondentIdFirst() {
        // Two confirmed threads sharing the SAME latestPublished: the comparator
        // must fall back to the deterministic id tie-break (higher correspondentId
        // first), so the order never depends on the input/dictionary iteration
        // order. Bob (300) sorts before Alice (200).
        let merged = InboxConversationMerger.merge(
            conversations: [
                Self.conversationRow(correspondent: PID.alice, name: "Alice", latestContent: "hi alice", latestPublished: 1000),
                Self.conversationRow(correspondent: PID.bob, name: "Bob", latestContent: "hi bob", latestPublished: 1000),
            ],
            outboundDMs: [],
            resolveCorrespondent: Self.resolver
        )

        #expect(merged.map(\.correspondentId) == [
            Lemmy.PersonID(PID.bob),
            Lemmy.PersonID(PID.alice),
        ])
    }
}
