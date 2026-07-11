//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

@MainActor
struct OfflineDownloadProgressViewModelTests {
    @Test
    func finishedWithWarningShowsTheWarning() {
        let vm = OfflineDownloadProgressViewModel(
            progress: OfflineDownloadProgress(
                phase: .finished, postsFetched: 80, totalPosts: 80, itemsCompleted: 80,
                warningMessage: "Downloaded 80 posts — some of the feed couldn't be reached."
            ),
            onCancel: { }
        )
        #expect(vm.statusText == "Downloaded 80 posts — some of the feed couldn't be reached.")
    }

    @Test
    func finishedWithoutWarningShowsDone() {
        let vm = OfflineDownloadProgressViewModel(
            progress: OfflineDownloadProgress(phase: .finished, postsFetched: 10, totalPosts: 10, itemsCompleted: 10),
            onCancel: { }
        )
        #expect(vm.statusText == "Done")
    }

    /// The three properties the status pill (`OfflineDownloadStatusView`) binds to
    /// reflect the content-phase snapshot — the pill reuses these rather than
    /// duplicating any formatting.
    @Test
    func contentPhaseBindingsReflectTheSnapshot() {
        let vm = OfflineDownloadProgressViewModel(
            progress: OfflineDownloadProgress(
                phase: .downloadingContent,
                postsFetched: 100,
                totalPosts: 100,
                itemsCompleted: 12
            ),
            onCancel: { }
        )
        #expect(vm.statusText == "Saving posts, comments & images — 12 of 100")
        // 0.3 (fetch phase) + 0.7 * 12/100 = 0.384.
        #expect(abs(vm.fraction - 0.384) < 0.0001)
        #expect(vm.accessibilityValueText == "38 percent, 12 of 100 posts saved")
    }

    /// Tapping the pill's ✕ invokes `onCancel` — the sole cancel path now that a
    /// dismissal no longer tears down the run.
    @Test
    func onCancelIsInvokedOnRequest() {
        var cancelled = false
        let vm = OfflineDownloadProgressViewModel(onCancel: { cancelled = true })
        vm.onCancel()
        #expect(cancelled == true)
    }
}
