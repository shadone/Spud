//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Drives ``OfflineDownloadProgressView``: holds the latest
/// ``OfflineDownloadProgress`` snapshot and exposes the strings the view binds
/// to. The hosting `PostListViewController` updates ``progress`` on the main
/// actor as it drains the download's `AsyncStream`, and invokes ``onCancel``
/// when the user taps Cancel.
///
/// Pure presentation: it does no I/O and holds no service reference, so it is
/// trivially testable and snapshot-friendly (seed a `progress` value and the
/// strings are deterministic).
@MainActor
@Observable
final class OfflineDownloadProgressViewModel {
    /// The latest progress snapshot. Defaults to a fresh `.fetchingPosts` so the
    /// sheet shows a sensible state the instant it appears, before the first
    /// stream value lands.
    var progress: OfflineDownloadProgress

    /// Invoked when the user taps Cancel. The controller cancels the in-flight
    /// download (it keeps draining until the terminal `.cancelled` lands, then
    /// dismisses the sheet).
    let onCancel: () -> Void

    init(
        progress: OfflineDownloadProgress = OfflineDownloadProgress(phase: .fetchingPosts),
        onCancel: @escaping () -> Void
    ) {
        self.progress = progress
        self.onCancel = onCancel
    }

    /// The `0...1` value for the determinate progress bar.
    var fraction: Double {
        progress.fractionCompleted
    }

    /// The phase-dependent status line under the progress bar, e.g.
    /// "Fetching posts…" or "Saving posts, comments & images — 12 of 100".
    var statusText: String {
        switch progress.phase {
        case .fetchingPosts:
            return NSLocalizedString(
                "Fetching posts…",
                comment: "Offline download status line during the feed-page fetch phase"
            )
        case .downloadingContent:
            let format = NSLocalizedString(
                "Saving posts, comments & images — %1$d of %2$d",
                comment: "Offline download status line during the content phase; %1 is completed, %2 is total"
            )
            return String(format: format, progress.itemsCompleted, progress.totalPosts)
        case .finished:
            return NSLocalizedString(
                "Done",
                comment: "Offline download status line when finished"
            )
        case .cancelled:
            return NSLocalizedString(
                "Cancelling…",
                comment: "Offline download status line while a cancel is settling"
            )
        case .failed:
            return progress.failureMessage ?? NSLocalizedString(
                "Couldn't download the feed.",
                comment: "Offline download fallback failure status line"
            )
        }
    }

    /// A VoiceOver-legible description of the bar's value — the percent plus the
    /// item counts during the content phase — so the progress is announced, not
    /// just shown.
    var accessibilityValueText: String {
        let percent = Int((fraction * 100).rounded())
        // Once the content phase has a known total (including a mid-content
        // cancel), announce the item counts alongside the percent; otherwise just
        // the percent (the fetch phase has no final denominator yet).
        let inContentPhase = progress.phase == .downloadingContent
            || (progress.phase == .cancelled && progress.totalPosts > 0)
        if inContentPhase {
            let format = NSLocalizedString(
                "%1$d percent, %2$d of %3$d posts saved",
                comment: "VoiceOver value for the offline download progress bar during the content phase"
            )
            return String(format: format, percent, progress.itemsCompleted, progress.totalPosts)
        }
        let format = NSLocalizedString(
            "%d percent",
            comment: "VoiceOver value for the offline download progress bar"
        )
        return String(format: format, percent)
    }
}
