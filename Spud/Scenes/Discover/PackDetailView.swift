//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// Detail for a starter pack: a header with its mosaic, blurb and a one-tap
/// "Follow all", then its member communities — each openable and individually
/// followable. Backed by the same ``DiscoverViewModel`` as the Discover home, so
/// follow state stays in sync across both.
struct PackDetailView: View {
    @Bindable var viewModel: DiscoverViewModel
    let pack: ResolvedStarterPack
    let accent: Color

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                Text("Included communities")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                ForEach(pack.communities) { row in
                    DiscoverCommunityRow(
                        row: row,
                        accent: accent,
                        onTap: { viewModel.open(row) },
                        followState: viewModel.followState(for: row),
                        onFollow: { viewModel.toggleFollow(row) }
                    )
                    .communityContextMenu(for: row, viewModel: viewModel)
                    Divider().padding(.leading, 68)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                PackMosaic(communities: pack.communities, size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color(.label))
                    Text("\(pack.communityCount) communities · \(DiscoverCommunityRow.compact(pack.totalSubscribers)) members")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                Spacer(minLength: 0)
            }
            Text(pack.blurb)
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))

            followAllControl
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var followAllControl: some View {
        if allFollowed {
            Label("Following all", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)
        } else {
            Button {
                viewModel.followAll(pack.communities)
            } label: {
                HStack(spacing: 6) {
                    if anyInFlight {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                    }
                    Text(followAllTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private var followAllTitle: String {
        let pending = pack.communities.filter { viewModel.followState(for: $0) == .idle }.count
        return pending == pack.communities.count
            ? "Follow all \(pack.communities.count)"
            : "Follow \(pending) more"
    }

    private var allFollowed: Bool {
        !pack.communities.isEmpty
            && pack.communities.allSatisfy { viewModel.followState(for: $0) == .following }
    }

    private var anyInFlight: Bool {
        pack.communities.contains { viewModel.followState(for: $0) == .inFlight }
    }
}
