//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import SwiftUI

/// Playful device-wide usage odometer: hero scroll distance with a
/// real-world equivalence, headline stat tiles, and the long tail of
/// counters. All data is local-only.
struct FunStatsView: View {
    let viewModel: FunStatsViewModel

    @State private var isConfirmingReset = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.tiles, id: \.key) { stat in
                        FunStatTile(stat: stat)
                    }
                }
                moreNumbers
                footer
            }
            .padding()
        }
        .background(Color(Theme.groupedBackground))
        .navigationTitle("Fun Stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Reset Stats", systemImage: "trash", role: .destructive) {
                        isConfirmingReset = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More options")
            }
        }
        .confirmationDialog(
            "Reset all fun stats? This cannot be undone.",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Stats", role: .destructive) {
                Task { await viewModel.resetStats() }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.needle")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("You have scrolled")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
            Text(viewModel.heroDistanceText)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
            if let equivalence = viewModel.heroEquivalence {
                Text(equivalence)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(Theme.secondaryGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var moreNumbers: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.moreRows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack {
                    Text(row.label)
                        .font(.subheadline)
                    Spacer()
                    Text(row.value)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal)
        .background(Color(Theme.secondaryGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let countingSince = viewModel.countingSinceText {
                Text(countingSince)
            } else {
                Text("Counting starts today")
            }
            Text("All data stays on this device.")
        }
        .font(.caption)
        .foregroundStyle(Color(.secondaryLabel))
        .frame(maxWidth: .infinity)
    }
}

/// SwiftUI rendition of the Activity Summary tile visual language
/// (`SummaryStatTileView` is UIKit and not directly reusable here).
private struct FunStatTile: View {
    let stat: SummaryStat

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: stat.icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
            Text(stat.value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(stat.label)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Color(Theme.secondaryGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.label): \(stat.value)")
    }
}
