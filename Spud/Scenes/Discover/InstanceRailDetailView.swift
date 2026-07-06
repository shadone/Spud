//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import SwiftUI

/// The full ranked instance list for the "Browse by instance" rail, reached from
/// its "See all". A vertical list of ``InstanceRow``; tapping one opens that
/// server's communities (the same drill-in the rail's cards use), via the shared
/// ``DiscoverViewModel``.
struct InstanceRailDetailView: View {
    let viewModel: DiscoverViewModel
    let instances: [InstanceSummary]
    let accent: Color

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(instances) { instance in
                    InstanceRow(instance: instance, accent: accent) {
                        viewModel.openInstance(instance)
                    }
                    Divider().padding(.leading, 68)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// A full-width instance row for the Browse-by-instance "See all" list: a letter
/// tile, the host, and a community / member / weekly-activity summary. Mirrors the
/// layout of ``DiscoverCommunityRow`` so the two lists read consistently. (The
/// rail's landing carousel uses the wider ``InstanceCard``; this is the list form.)
struct InstanceRow: View {
    let instance: InstanceSummary
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CommunityHueIcon(name: instance.host, title: instance.host, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.host)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(instance.host), \(instance.communityCount) communities")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }

    private var summary: String {
        let communities = "\(instance.communityCount) communities"
        let members = "\(CountFormatter.string(instance.totalSubscribers)) members"
        let active = "\(CountFormatter.string(instance.totalActiveWeek))/wk"
        return "\(communities) · \(members) · \(active)"
    }
}
