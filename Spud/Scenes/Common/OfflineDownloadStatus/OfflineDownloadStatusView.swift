//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import SwiftUI

/// The persistent, non-blocking status pill shown while a feed downloads for
/// offline browsing: a determinate progress ring bound to
/// ``OfflineDownloadProgress/fractionCompleted``, a phase-aware status line, and
/// a trailing ✕ that cancels the run.
///
/// Unlike the retired modal progress sheet, this pill is anchored to the window
/// by ``OfflineDownloadStatusPresenter`` and survives feed switches and tab
/// switches — the user can dismiss the chooser and keep using the app while the
/// download continues. Dismissing the pill does **not** cancel the download; only
/// the ✕ does (it routes through ``OfflineDownloadProgressViewModel/onCancel``).
///
/// Driven entirely by ``OfflineDownloadProgressViewModel`` (an `@Observable`
/// snapshot the controller updates as it drains the download stream), reusing its
/// `statusText` / `fraction` / `accessibilityValueText` — no presentation logic is
/// duplicated here. Because it binds to the observable view model, the drain
/// loop's writes re-render the pill automatically. Pure presentation, so it is
/// deterministic to snapshot.
struct OfflineDownloadStatusView: View {
    let viewModel: OfflineDownloadProgressViewModel

    /// Hairline border, matching the toast pill's treatment.
    private let hairline: CGFloat = 0.5

    var body: some View {
        HStack(spacing: 12) {
            // Ring + status line form a single VoiceOver element with an explicit
            // value (the percent + item counts) so progress is announced, not just
            // shown — mirroring the retired progress sheet's a11y treatment.
            HStack(spacing: 12) {
                OfflineDownloadProgressRing(fraction: viewModel.fraction)
                    .frame(width: 24, height: 24)

                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(NSLocalizedString(
                "Saving for offline",
                comment: "VoiceOver label for the offline-download status pill"
            )))
            .accessibilityValue(Text(viewModel.accessibilityValueText))

            Button {
                viewModel.onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString(
                "Cancel download",
                comment: "VoiceOver label for the ✕ button on the offline-download status pill"
            )))
        }
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: hairline)
        )
    }
}

/// A compact determinate progress ring for the offline-download status pill: a
/// faint track under an accent-tinted arc trimmed to `fraction`. Extracted as its
/// own small view so the pill body stays legible.
///
/// A tiny floor (2%) keeps a sliver of the arc visible at 0 so the ring never
/// reads as an empty circle the instant the download starts.
struct OfflineDownloadProgressRing: View {
    let fraction: Double

    private var clampedFraction: CGFloat {
        CGFloat(min(1, max(0.02, fraction)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 3)
            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    Color(uiColor: ThemeManager.currentAccentColor),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: fraction)
        }
    }
}

#Preview {
    OfflineDownloadStatusView(
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
    .padding()
}
