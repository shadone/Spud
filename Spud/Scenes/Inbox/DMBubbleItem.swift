//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// One rendered bubble in a DM thread.
///
/// A thread is a merge of two sources (see `DMThreadViewModel.recompute`):
/// confirmed messages from the persistent `privateMessage` store and still
/// pending/failed outbound sends from the composer outbox. Both flow into this
/// single render model so the diffable data source and cell provider stay
/// agnostic of where a bubble came from.
///
/// `id` must be unique and stable across both sources. Confirmed messages use
/// their (positive) server message id; optimistic sends use a large *negative*
/// synthetic id derived from the outbound row id (see
/// `DMThreadViewModel.optimisticBubbleId(for:)`), so the two id spaces never
/// collide — mirroring the post-detail pending-comment merge.
struct DMBubbleItem: Hashable, Identifiable {
    /// Sending lifecycle of an *optimistic* (outbound) bubble. A confirmed
    /// message has no status (`nil`) — it is delivered.
    enum PendingStatus: Hashable {
        /// Queued or actively sending: shown dimmed with a "Sending…" line.
        case sending
        /// Permanently failed: shown with a "Not delivered — tap to retry"
        /// affordance that opens a Retry / Discard action sheet.
        case failed
    }

    /// Unique, stable bubble id (positive = confirmed server message; negative =
    /// optimistic outbound row).
    let id: Int64
    /// The message text.
    let content: String
    /// Publish/creation timestamp; drives the chat ordering (oldest first).
    let published: Date
    /// Whether the bubble is the account holder's (right-aligned, accent tint).
    let isOutgoing: Bool
    /// `nil` for a confirmed message; `.sending`/`.failed` for an optimistic one.
    let pendingStatus: PendingStatus?
    /// The outbound row's client token, present only on an optimistic bubble so a
    /// failed send can be retried / discarded. `nil` for a confirmed message.
    let clientToken: String?

    /// `true` when this bubble represents a still-pending/failed optimistic send.
    var isOptimistic: Bool {
        pendingStatus != nil
    }
}
