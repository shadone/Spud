//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import SwiftUI

/// The "Browse by instance" drill-in: every curated-safe community hosted on a
/// single server, under an instance info card (the "Instance lens" from the Spud
/// Design Discover mockup). The card is an elevated, tappable summary — globe,
/// host, members and community count, a character blurb, a trust read and a
/// "Health, uptime & trust" affordance — that drills into the richer instance
/// detail screen. The section header carries an inline sort control for the list.
/// Reuses ``DiscoverCommunityRow`` so opening and inline Subscribe behave exactly
/// as on the Discover home — the same ``DiscoverViewModel`` backs both, so a
/// subscription here is reflected when the user navigates back.
struct InstanceCommunitiesView: View {
    @Bindable var viewModel: DiscoverViewModel
    let host: String
    /// Snapshot of the host's curated-safe communities, resolved when the screen
    /// was pushed. Re-sorted in place by the inline sort control.
    let communities: [CommunityListRow]
    /// Instance directory metadata for the info card; nil when the host has no
    /// Explorer instance record (the card then degrades to host + community count
    /// and is not tappable).
    let instanceInfo: SiteListRow?
    let accent: Color
    /// Opens the richer instance detail screen. The card only offers the tap (and
    /// shows its disclosure chevron) when there's instance info to drill into.
    var onOpenDetail: (() -> Void)?

    /// Per-screen sort for the community list, defaulting to Activity (matching
    /// the Discover design). Independent of the Discover home's sort.
    @State private var sort: ExplorerCommunitySort = .mostActive

    /// Sorts offered by the inline control, matching the Discover design.
    private static let sortOptions: [ExplorerCommunitySort] = [.mostActive, .members, .name, .newest]

    /// Whether the lens card drills into the instance detail screen.
    private var canOpenDetail: Bool {
        instanceInfo != nil && onOpenDetail != nil
    }

    private var displayedCommunities: [CommunityListRow] {
        ExplorerCommunityDirectory.sorted(communities, by: sort)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                instanceCard
                sectionHeader
                ForEach(displayedCommunities) { row in
                    DiscoverCommunityRow(
                        row: row,
                        accent: accent,
                        onTap: { viewModel.open(row) },
                        subscriptionState: viewModel.subscriptionState(for: row),
                        onSubscribe: { viewModel.toggleSubscription(row) },
                        subtitleLineLimit: nil,
                        showsQualifiedHandle: false
                    )
                    .communityContextMenu(for: row, viewModel: viewModel)
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
        .sensoryFeedback(.selection, trigger: sort)
    }

    // MARK: - Instance info card

    @ViewBuilder
    private var instanceCard: some View {
        if canOpenDetail {
            Button { onOpenDetail?() } label: { instanceCardContent }
                .buttonStyle(InstanceCardButtonStyle(accent: accent))
                .accessibilityHint("Opens server details")
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 4)
        } else {
            instanceCardContent
                .padding(.init(top: 13, leading: 13, bottom: 13, trailing: 11))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 4)
        }
    }

    private var instanceCardContent: some View {
        HStack(alignment: .center, spacing: 13) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.15))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: "globe")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accent)
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(host)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color(.label))
                Text(statsLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.top, 1)
                if let blurb {
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                }
                metadataChips
                if instanceInfo != nil {
                    HStack(spacing: 11) {
                        if let trust {
                            trustRead(trust)
                        }
                        if canOpenDetail {
                            HStack(spacing: 3) {
                                Text("Health, uptime & trust")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            Spacer(minLength: 0)
            if canOpenDetail {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }

    private func trustRead(_ signal: HealthSignal) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(trustColor(signal.level))
                .frame(width: 7, height: 7)
            Text(signal.label)
                .font(.caption2)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: - Live NodeInfo chips

    /// Software + open-signups chips fed by a live NodeInfo probe
    /// (``DiscoverViewModel/metadata(forHost:)``). Absent until the probe resolves
    /// and absent entirely when it fails (fail-open — no placeholder). Distinct
    /// from the Explorer-directory trust read below: these carry the instance's own
    /// live self-report (what software it runs, whether signups are open now).
    @ViewBuilder
    private var metadataChips: some View {
        if let metadata = viewModel.metadata(forHost: host) {
            HStack(spacing: 7) {
                softwareChip(for: metadata)
                if let openRegistrations = metadata.openRegistrations {
                    signupsChip(open: openRegistrations)
                }
            }
            .padding(.top, 8)
        }
    }

    /// The software identity chip, e.g. "Lemmy 0.19.11" (display name + live
    /// version) or the bare display name when no version is advertised.
    private func softwareChip(for metadata: InstanceMetadata) -> some View {
        let profile = PlatformProfile.profile(for: metadata.software, version: metadata.version)
        let text: String
        if let version = metadata.version, !version.isEmpty {
            text = "\(profile.displayName) \(version)"
        } else {
            text = profile.displayName
        }
        return chip(icon: "shippingbox.fill", text: text, tint: accent)
    }

    /// The live open-registrations chip: green "Open signups" when the instance
    /// accepts new members now, neutral "Signups closed" otherwise.
    private func signupsChip(open: Bool) -> some View {
        chip(
            icon: open ? "person.fill.badge.plus" : "lock.fill",
            text: open ? "Open signups" : "Signups closed",
            tint: open ? Color(.systemGreen) : Color(.secondaryLabel)
        )
    }

    private func chip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Section header + inline sort

    private var sectionHeader: some View {
        HStack(alignment: .center) {
            Text("Communities on \(host)")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
            Spacer(minLength: 8)
            sortMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 7)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort communities", selection: $sort) {
                ForEach(Self.sortOptions, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Text(sortShortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.label))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemFill), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
        }
        .accessibilityLabel("Sort communities")
    }

    // MARK: - Derived content

    /// "X members · Y communities" when the instance's member count is known,
    /// otherwise just the community count shown below.
    private var statsLine: String {
        let communityText = "\(CountFormatter.string(Int64(communities.count))) communities"
        if let members = instanceInfo?.usersTotal, members > 0 {
            return "\(CountFormatter.string(members)) members · \(communityText)"
        }
        return communityText
    }

    private var blurb: String? {
        guard let text = instanceInfo?.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    /// Trust read derived from the Explorer score, or nil when there's no instance
    /// record to read it from. A zero score reads as "Unrated" rather than low.
    private var trust: HealthSignal? {
        guard let instanceInfo else { return nil }
        let score100 = instanceInfo.score > 0 ? instanceInfo.score * 100 : nil
        return ExplorerInstanceHealth.trust(score100: score100, suspicious: false)
    }

    /// Short pill label for the active sort, matching the Discover design.
    private var sortShortTitle: String {
        switch sort {
        case .mostActive: "Activity"
        case .members: "Members"
        case .name: "Name"
        case .newest: "Newest"
        case .recommended: "Recommended"
        }
    }

    private func trustColor(_ level: HealthLevel) -> Color {
        switch level {
        case .good: Color(.systemGreen)
        case .ok: Color(.systemOrange)
        case .bad: Color(.systemRed)
        case .unknown: Color(.tertiaryLabel)
        }
    }
}

/// Card press feedback for the tappable instance lens: an elevated fill with a
/// hairline border that switches to the accent on press (matching the Discover
/// mockup's pressed state).
private struct InstanceCardButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.init(top: 13, leading: 13, bottom: 13, trailing: 11))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        configuration.isPressed ? accent : Color(.separator),
                        lineWidth: configuration.isPressed ? 1.5 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
