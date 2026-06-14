//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// The "Browse by instance" drill-in: every curated-safe community hosted on a
/// single server. Reuses ``DiscoverCommunityRow`` so opening and inline Follow
/// behave exactly as on the Discover home — the same ``DiscoverViewModel`` backs
/// both, so a follow here is reflected when the user navigates back.
struct InstanceCommunitiesView: View {
    @Bindable var viewModel: DiscoverViewModel
    let host: String
    /// Snapshot of the host's communities, resolved when the screen was pushed.
    let communities: [CommunityListRow]
    let accent: Color

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                ForEach(communities) { row in
                    DiscoverCommunityRow(
                        row: row,
                        accent: accent,
                        onTap: { viewModel.open(row) },
                        followState: viewModel.followState(for: row),
                        onFollow: { viewModel.follow(row) }
                    )
                    Divider().padding(.leading, 68)
                }

                if communities.isEmpty {
                    Text("No communities to show for this server.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.caption)
                .foregroundStyle(accent)
            Text("\(communities.count) communities on \(host)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
