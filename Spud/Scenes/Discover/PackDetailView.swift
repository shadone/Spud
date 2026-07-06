//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import SwiftUI

/// Detail for a starter pack: a header with its mosaic, blurb and a one-tap
/// "Subscribe to all", then its member communities — each openable and
/// individually subscribable. Backed by the same ``DiscoverViewModel`` as the
/// Discover home, so subscription state stays in sync across both.
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
                        subscriptionState: viewModel.subscriptionState(for: row),
                        onSubscribe: { viewModel.toggleSubscription(row) }
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
                    Text("\(pack.communityCount) communities · \(CountFormatter.string(pack.totalSubscribers)) members")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                Spacer(minLength: 0)
            }
            Text(pack.blurb)
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))

            subscribeToAllControl
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var subscribeToAllControl: some View {
        if allSubscribed {
            Label("Subscribed to all", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)
        } else {
            Button {
                viewModel.subscribeToAll(pack.communities)
            } label: {
                HStack(spacing: 6) {
                    if anyInFlight {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                    }
                    Text(subscribeToAllTitle)
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

    private var subscribeToAllTitle: String {
        let pending = pack.communities.filter { viewModel.subscriptionState(for: $0) == .idle }.count
        return pending == pack.communities.count
            ? "Subscribe to all \(pack.communities.count)"
            : "Subscribe to \(pending) more"
    }

    private var allSubscribed: Bool {
        !pack.communities.isEmpty
            && pack.communities.allSatisfy { viewModel.subscriptionState(for: $0) == .subscribed }
    }

    private var anyInFlight: Bool {
        pack.communities.contains { viewModel.subscriptionState(for: $0) == .inFlight }
    }
}
