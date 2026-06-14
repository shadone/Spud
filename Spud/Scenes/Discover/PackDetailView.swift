//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// Detail for a starter pack: a header with its mosaic and blurb, then its
/// member communities, each opening its page (where Subscribe lives). A
/// one-tap "Follow all" is deferred until inline follow lands.
struct PackDetailView: View {
    let pack: ResolvedStarterPack
    let accent: Color
    let onOpenCommunity: (CommunityListRow) -> Void

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
                    DiscoverCommunityRow(row: row, accent: accent) { onOpenCommunity(row) }
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}
