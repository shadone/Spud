//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import SwiftUI

/// The same-name compare target: a community name carried by more than one
/// server, with every variant ranked busiest-first. Drives the compare sheet.
struct CompareTarget: Identifiable, Equatable {
    let name: String
    let displayName: String
    let variants: [CommunityListRow]

    var id: String {
        name
    }
}

/// Lets the user pick between same-name communities on different servers. These
/// are independent communities — not copies — so the sheet leads with that and
/// then ranks the variants by recent activity so the liveliest is obvious.
struct CompareSheetView: View {
    /// Read for live per-variant subscription state; reading `subscriptionState(for:)`
    /// in the body subscribes the sheet to the view model's in-flight / subscribed
    /// sets, so the inline Subscribe pills update in place (this `@Observable` is
    /// tracked even through a plain `let`).
    let viewModel: DiscoverViewModel
    let target: CompareTarget
    let accent: Color
    let onOpenCommunity: (CommunityListRow) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    callout
                    ForEach(Array(target.variants.enumerated()), id: \.element.id) { index, row in
                        VariantRow(
                            row: row,
                            accent: accent,
                            rank: index,
                            subscriptionState: viewModel.subscriptionState(for: row),
                            onTap: { onOpenCommunity(row) },
                            onSubscribe: { viewModel.toggleSubscription(row) }
                        )
                        if index < target.variants.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("c/\(target.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(accent)
            Text("These are independent communities on different servers that happen to share the name “\(target.displayName)”. Pick the one you want to subscribe to.")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Variant row

struct VariantRow: View {
    let row: CommunityListRow
    let accent: Color
    /// Position in the busiest-first ranking; the leader gets a subtle badge.
    let rank: Int
    /// Inline subscription state; ignored unless `onSubscribe` is supplied.
    var subscriptionState: CommunitySubscriptionState = .idle
    let onTap: () -> Void
    /// When set, a trailing Subscribe control replaces the disclosure chevron so the
    /// variant can be subscribed in place; the row tap still opens the community.
    var onSubscribe: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            CommunityIcon(iconUrl: row.iconUrl, name: row.name, title: row.displayName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.instanceHost)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                    if rank == 0 {
                        Text("Most active")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                }
                Text("\(CountFormatter.string(row.numberOfSubscribers)) members · \(CountFormatter.string(row.usersActiveWeek))/wk")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 0)
            if let onSubscribe {
                SubscribeButton(state: subscriptionState, accent: accent, action: onSubscribe)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityActions {
            if let onSubscribe {
                Button(subscriptionState == .subscribed ? "Unsubscribe" : "Subscribe", action: onSubscribe)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [row.instanceHost]
        if rank == 0 { parts.append("most active") }
        parts.append("\(CountFormatter.string(row.numberOfSubscribers)) members")
        if subscriptionState == .subscribed { parts.append("Subscribed") }
        return parts.joined(separator: ", ")
    }
}
