//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import SwiftUI
import UIKit

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
        // Liquid Glass surface: replaces the flat `secondarySystemBackground`
        // fill, drop shadow, and hairline stroke this pill used to draw by
        // hand. The capsule's own glass material now supplies the surface,
        // elevation, and edge — layering a flat shadow/stroke underneath it
        // would double up on a real glass surface's own depth cue (same
        // reasoning as `ToastView`, the other window-anchored HUD pill this
        // one is structurally modeled on). `.interactive()` matches
        // `GlassTokens.controlSurface` (SpudUIKit's UIKit-side token for this
        // exact case) since the pill hosts a real tap target (the cancel
        // button) — SwiftUI's `glassEffect` API is a distinct type from
        // UIKit's `UIGlassEffect`, so the token itself can't be reused here,
        // but the material/interactivity choice is kept identical.
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
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

    /// The implicit animation for the arc's trim, or `nil` under Reduce Motion.
    ///
    /// Reduce Motion removes the *motion*, not the information: `nil` makes the
    /// arc jump straight to its new length on every progress tick, so the ring
    /// still reports how far along the download is — it just stops sweeping
    /// there. (There is no continuous spin or pulse to suppress; the tween
    /// between two progress values is the only motion this ring produces.)
    ///
    /// Pure and static so the decision is unit-testable without rendering a
    /// view, matching ``FreshWashState/resolve(isNew:hasAnimated:reduceMotion:)``.
    static func trimAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 3)
            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    // The arc is a meaningful indicator drawn on the pill, not a
                    // fill, so it takes the accent's content variant - the vivid
                    // accent measured near 2.2:1 against the light pill on the
                    // brightest accents, under the 3:1 WCAG asks of a graphic.
                    Color(uiColor: ThemeManager.currentContentAccentColor),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // `UIAccessibility.isReduceMotionEnabled` rather than
                // `@Environment(\.accessibilityReduceMotion)`: every other motion
                // gate in the app spells it this way (ToastPresenter, this pill's
                // own presenter, the media viewer, the comment fresh-wash), and a
                // single grep has to keep finding all of them. Like those, it is
                // read where the animation happens and is not observed for runtime
                // changes — here that costs nothing, because the ring only exists
                // while a download runs and `fraction` re-evaluates this body on
                // every progress tick, so a mid-download toggle takes effect on the
                // next update.
                .animation(
                    Self.trimAnimation(reduceMotion: UIAccessibility.isReduceMotionEnabled),
                    value: fraction
                )
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
