//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// The full ranked list for a Discover community rail (Trending / Rising / Because
/// you follow), reached from the rail's "See all". Renders the same
/// ``DiscoverCommunityRow`` as the All-communities directory — so Subscribe, the
/// long-press context menu, and tap-to-open behave identically — backed by the
/// same ``DiscoverViewModel``, so subscription state stays in sync with the
/// landing as the user subscribes here.
///
/// The same-name "compare across servers" action is intentionally not offered here
/// (that sheet is presented by the Discover landing, and a community is reachable
/// by tapping its row); the "also on N servers" badge still shows as context.
struct RailDetailView: View {
    /// Read for live subscription state; reading `subscriptionState(for:)` in the
    /// body subscribes this screen to the view model's in-flight / subscribed sets
    /// (the `@Observable` is tracked even through a plain `let`).
    let viewModel: DiscoverViewModel
    let rows: [CommunityListRow]
    let accent: Color

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    DiscoverCommunityRow(
                        row: row,
                        accent: accent,
                        onTap: { viewModel.open(row) },
                        subscriptionState: viewModel.subscriptionState(for: row),
                        onSubscribe: { viewModel.toggleSubscription(row) },
                        blurNsfw: viewModel.blurNsfw
                    )
                    .communityContextMenu(for: row, viewModel: viewModel)
                    Divider().padding(.leading, 68)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }
}
