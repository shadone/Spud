//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit

/// Merges the persisted conversation list (`observeConversations`) with the
/// account's still-pending outbound DM rows (`observeOutboundDirectMessages`)
/// into the render-ready `[InboxConversation]`, newest-thread first.
///
/// Pure and side-effect-free so the non-trivial merge can be unit-tested in
/// isolation (`InboxConversationMergerTests`). The view-model supplies the live
/// data via observations and a recipient name/avatar resolver.
///
/// The merge mirrors the single-thread merge in `DMThreadViewModel`, lifted to
/// the conversation granularity:
///
/// 1. **Status indicator on an existing thread.** A confirmed conversation that
///    also has pending/sending/failed outbound DMs to its correspondent gets a
///    `pendingStatus`: `.failed` if ANY outbound row failed (failed dominates so
///    the user is alerted), else `.sending`. The newest outbound row's body/time
///    also becomes the row's preview when it is newer than the latest confirmed
///    message — so the row reads as "you just sent this", matching iMessage.
/// 2. **Synthetic pending-only conversation.** A correspondent with outbound DMs
///    but NO confirmed conversation (a brand-new first message) is synthesized as
///    a conversation row, ordered by its newest outbound `createdAt`, with the
///    name/avatar resolved from the person store (falling back to a neutral label
///    when the recipient isn't known yet).
/// 3. **Collapse by correspondent id.** Because both sources key on the
///    correspondent's server person id, a synthetic pending-only row collapses
///    into the real thread the instant the server copy lands: the confirmed row
///    then exists, so the outbound rows attach to it (case 1) instead of
///    synthesizing a duplicate (case 2). When the send confirms, the performer
///    deletes the outbound row, `observeOutboundDirectMessages` re-emits without
///    it, and the `pendingStatus` clears — the same self-healing reconcile as the
///    thread.
enum InboxConversationMerger {
    /// Resolves a pending-only correspondent's display info. Returns nil for the
    /// name when the recipient person isn't in the store yet (the merge then uses
    /// a neutral fallback label).
    struct CorrespondentInfo {
        var name: String?
        var avatarUrl: URL?
    }

    /// Merge `conversations` (confirmed, newest-first) with `outboundDMs`
    /// (pending/sending/failed SEND rows across all recipients, draft-excluded),
    /// returning the render-ready conversations newest-thread first.
    ///
    /// - Parameters:
    ///   - conversations: persisted conversation rows from `observeConversations`.
    ///   - outboundDMs: outbound DM rows from `observeOutboundDirectMessages`
    ///     (each carries a `recipientServerPersonId`).
    ///   - resolveCorrespondent: looks up a pending-only correspondent's
    ///     name/avatar by server person id (the view-model wires this to the
    ///     person store).
    static func merge(
        conversations: [PrivateMessageConversationRow],
        outboundDMs: [OutboundContentRecord],
        resolveCorrespondent: (Int64) -> CorrespondentInfo
    ) -> [InboxConversation] {
        // Group outbound DM rows by recipient server person id. A nil recipient
        // is a malformed row (a DM always carries one) — skip it rather than
        // collapsing every such row onto a phantom recipient 0.
        var outboundByRecipient: [Int64: [OutboundContentRecord]] = [:]
        for record in outboundDMs {
            guard let recipient = record.recipientServerPersonId else { continue }
            outboundByRecipient[recipient, default: []].append(record)
        }

        var result: [InboxConversation] = []

        // Case 1: confirmed conversations, decorated with any pending state.
        for row in conversations {
            let pending = outboundByRecipient.removeValue(forKey: row.correspondentServerPersonId)
            result.append(makeConversation(confirmed: row, pending: pending))
        }

        // Case 2: synthetic pending-only conversations (recipients left in the
        // map have outbound rows but no confirmed thread).
        for (recipient, records) in outboundByRecipient {
            let info = resolveCorrespondent(recipient)
            result.append(makeSyntheticConversation(recipient: recipient, records: records, info: info))
        }

        // Newest-thread first; tie-break on id so the order is deterministic.
        return result.sorted {
            $0.latestPublished == $1.latestPublished
                ? Int64($0.correspondentId) > Int64($1.correspondentId)
                : $0.latestPublished > $1.latestPublished
        }
    }

    // MARK: - Construction

    /// Build a conversation row from a confirmed thread, folding in any pending
    /// outbound rows for the same correspondent.
    private static func makeConversation(
        confirmed row: PrivateMessageConversationRow,
        pending: [OutboundContentRecord]?
    ) -> InboxConversation {
        let status = pendingStatus(for: pending)

        // When the newest pending send is newer than the latest confirmed
        // message, preview it instead so the row reads as "you just sent this".
        var latestContent = row.latestContent
        var latestPublished = row.latestPublished
        if let newest = newestOutbound(pending) {
            let createdAt = Date(timeIntervalSince1970: newest.createdAt)
            if createdAt > latestPublished {
                latestContent = newest.body
                latestPublished = createdAt
            }
        }

        return InboxConversation(
            correspondentId: Lemmy.PersonID(row.correspondentServerPersonId),
            correspondentName: row.correspondentName ?? unknownCorrespondentName,
            correspondentAvatarUrl: row.correspondentAvatarUrl.flatMap { URL(string: $0) },
            latestContent: latestContent,
            latestPublished: latestPublished,
            unreadCount: row.unreadCount,
            pendingStatus: status
        )
    }

    /// Build a synthetic conversation row for a recipient that has outbound DMs
    /// but no confirmed thread yet (a brand-new first message).
    private static func makeSyntheticConversation(
        recipient: Int64,
        records: [OutboundContentRecord],
        info: CorrespondentInfo
    ) -> InboxConversation {
        let newest = newestOutbound(records)
        let createdAt = newest.map { Date(timeIntervalSince1970: $0.createdAt) } ?? .distantPast
        return InboxConversation(
            correspondentId: Lemmy.PersonID(recipient),
            correspondentName: info.name ?? unknownCorrespondentName,
            correspondentAvatarUrl: info.avatarUrl,
            latestContent: newest?.body ?? "",
            latestPublished: createdAt,
            // A brand-new outgoing thread has no incoming messages, so nothing is
            // unread.
            unreadCount: 0,
            pendingStatus: pendingStatus(for: records)
        )
    }

    // MARK: - Helpers

    /// Failed dominates sending so a delivery failure is always surfaced; nil/empty
    /// means nothing is in flight.
    private static func pendingStatus(for records: [OutboundContentRecord]?) -> InboxConversationPendingStatus? {
        guard let records, !records.isEmpty else { return nil }
        if records.contains(where: { $0.status == OutboundStatus.failed.rawValue }) {
            return .failed
        }
        return .sending
    }

    /// The most recently created outbound row (`createdAt`), if any.
    private static func newestOutbound(_ records: [OutboundContentRecord]?) -> OutboundContentRecord? {
        records?.max { $0.createdAt < $1.createdAt }
    }

    /// Neutral label for a correspondent whose person row isn't in the store yet.
    private static let unknownCorrespondentName = NSLocalizedString(
        "Unknown",
        comment: "Inbox conversation fallback name for an unresolved DM correspondent"
    )
}
