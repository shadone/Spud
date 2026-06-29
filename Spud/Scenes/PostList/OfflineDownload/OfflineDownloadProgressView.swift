//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import SwiftUI

/// The compact sheet shown while a feed is downloading for offline browsing:
/// a title, a determinate progress bar bound to
/// ``OfflineDownloadProgress/fractionCompleted``, a phase-aware status line, and
/// a Cancel button.
///
/// Driven entirely by ``OfflineDownloadProgressViewModel`` (an `@Observable`
/// snapshot the controller updates as it drains the download stream), so the
/// view itself does no work and is deterministic to snapshot.
struct OfflineDownloadProgressView: View {
    let viewModel: OfflineDownloadProgressViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color(uiColor: ThemeManager.currentAccentColor))
                    .accessibilityHidden(true)

                Text(NSLocalizedString(
                    "Saving for offline",
                    comment: "Title of the offline-download progress sheet"
                ))
                .font(.headline)
            }

            VStack(spacing: 10) {
                ProgressView(value: viewModel.fraction)
                    .tint(Color(uiColor: ThemeManager.currentAccentColor))
                    // The status line below already carries the human-readable
                    // counts; expose the same as the bar's VoiceOver value so the
                    // progress is announced, not just shown.
                    .accessibilityLabel(Text(NSLocalizedString(
                        "Download progress",
                        comment: "VoiceOver label for the offline download progress bar"
                    )))
                    .accessibilityValue(Text(viewModel.accessibilityValueText))

                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    // The status text already reflects the counts; merge it into
                    // the progress element so VoiceOver doesn't read it twice.
                    .accessibilityHidden(true)
            }

            Button(role: .cancel) {
                viewModel.onCancel()
            } label: {
                Text(NSLocalizedString(
                    "Cancel",
                    comment: "Cancel button on the offline-download progress sheet"
                ))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    OfflineDownloadProgressView(
        viewModel: OfflineDownloadProgressViewModel(
            progress: OfflineDownloadProgress(
                phase: .downloadingContent,
                postsFetched: 100,
                totalPosts: 100,
                itemsCompleted: 12
            ),
            onCancel: { }
        )
    )
}
