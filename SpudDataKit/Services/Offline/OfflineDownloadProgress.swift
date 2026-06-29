//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Progress snapshot for an in-flight (or finished) offline feed download.
///
/// Emitted on the `AsyncStream` returned by
/// ``OfflineDownloadService/download(feed:lemmyService:accountId:siteId:commentSort:showNsfw:)``.
/// The download runs in two phases: first it bulk-fetches feed pages (counted by
/// ``postsFetched``), then it downloads each post's comment tree and images
/// (counted by ``itemsCompleted`` out of ``totalPosts``). The UI derives a
/// `0...1` fraction from these counters (see ``fractionCompleted``).
///
/// This is a value type so it can cross the actor boundary to the main-actor UI.
public struct OfflineDownloadProgress: Sendable, Equatable {
    /// Which stage of the download the snapshot describes.
    public enum Phase: Sendable, Equatable {
        /// Fetching and persisting feed pages. ``postsFetched`` grows as pages
        /// land; ``totalPosts`` is not yet final.
        case fetchingPosts
        /// Downloading per-post content (comment trees + images).
        /// ``itemsCompleted`` grows towards ``totalPosts``.
        case downloadingContent
        /// Every target post's content has been processed (best-effort: some
        /// individual fetches may have failed without aborting the run).
        case finished
        /// The download stopped on a fatal error (e.g. the very first feed page
        /// failed while online). See ``failureMessage``.
        case failed
        /// The download was cancelled (the consuming task was cancelled / the
        /// stream terminated). Partial content already on disk is kept.
        case cancelled
    }

    /// The current stage of the download.
    public var phase: Phase

    /// Number of posts persisted to the database so far by the page-fetch loop.
    /// During ``Phase/fetchingPosts`` this climbs page by page.
    public var postsFetched: Int

    /// The total number of posts the content phase will process. Zero until the
    /// page-fetch phase finishes and the download targets are read, then fixed
    /// for the rest of the run. Capped at the service's `maxPosts`.
    public var totalPosts: Int

    /// Number of target posts whose content (comments + images) has been
    /// processed. A post counts as completed even when one of its individual
    /// fetches failed (best-effort per item).
    public var itemsCompleted: Int

    /// A human-readable description of a fatal failure, set only when
    /// ``phase`` is ``Phase/failed``.
    public var failureMessage: String?

    public init(
        phase: Phase,
        postsFetched: Int = 0,
        totalPosts: Int = 0,
        itemsCompleted: Int = 0,
        failureMessage: String? = nil
    ) {
        self.phase = phase
        self.postsFetched = postsFetched
        self.totalPosts = totalPosts
        self.itemsCompleted = itemsCompleted
        self.failureMessage = failureMessage
    }

    /// A `0...1` completion fraction for a progress bar.
    ///
    /// Weighting: fetching the feed pages is the first 30% of the work, and
    /// downloading per-post content is the remaining 70% (the content phase is
    /// far more network-heavy — a comment tree + up to two images per post).
    /// During the fetch phase the fraction is capped at 0.3 since the eventual
    /// total isn't known yet; `.finished` is always 1.
    public var fractionCompleted: Double {
        switch phase {
        case .finished:
            return 1
        case .failed, .cancelled:
            // Reflect whatever progress was made before stopping. When the run
            // stopped during the fetch phase (`totalPosts` not yet known), fall
            // back to the same bounded climb the `.fetchingPosts` case uses
            // rather than snapping the bar to 0 even though N posts were
            // fetched.
            guard totalPosts > 0 else {
                return min(0.3, Double(postsFetched) / 200.0)
            }
            return 0.3 + 0.7 * (Double(itemsCompleted) / Double(totalPosts))
        case .fetchingPosts:
            // Unknown denominator while paging; show a small, bounded climb so
            // the bar moves but never implies the fetch phase is finished.
            return min(0.3, Double(postsFetched) / 200.0)
        case .downloadingContent:
            guard totalPosts > 0 else { return 0.3 }
            return 0.3 + 0.7 * (Double(itemsCompleted) / Double(totalPosts))
        }
    }
}
