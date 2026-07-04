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
}
