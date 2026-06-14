//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// The Discover (Community Explorer) landing. Shows activity-driven rails —
/// Trending and Rising — over a sortable "All communities" directory. While the
/// user is searching, the rails step aside and only the filtered directory
/// shows. Tapping a community opens its page (where Subscribe lives).
struct DiscoverView: View {
    @Bindable var viewModel: DiscoverViewModel
    /// The app-wide accent, passed from the hosting controller so it tracks the
    /// user's chosen tint.
    let accent: Color

    var body: some View {
        Group {
            if viewModel.isLoading {
                loading
            } else {
                content
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $viewModel.compareTarget) { target in
            CompareSheetView(
                target: target,
                accent: accent,
                onOpenCommunity: { viewModel.openFromCompare($0) },
                onDismiss: { viewModel.compareTarget = nil }
            )
        }
    }

    private var loading: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if !viewModel.isSearching {
                    if !viewModel.isSignedIn {
                        signedOutNote
                    }
                    packsRail
                    rail(
                        title: "Trending now",
                        subtitle: "Most weekly activity across the network",
                        rows: viewModel.trending,
                        momentum: false
                    )
                    rail(
                        title: "Rising",
                        subtitle: "Small communities, big momentum",
                        rows: viewModel.rising,
                        momentum: true
                    )
                    rail(
                        title: "Because you follow",
                        subtitle: "More from servers you're on",
                        rows: viewModel.becauseYouFollow,
                        momentum: false
                    )
                    instanceRail
                }

                directoryHeader

                ForEach(shownDirectory) { row in
                    DiscoverCommunityRow(
                        row: row,
                        accent: accent,
                        onTap: { viewModel.open(row) },
                        onCompare: { viewModel.compare(row) },
                        followState: viewModel.followState(for: row),
                        onFollow: { viewModel.follow(row) }
                    )
                    Divider().padding(.leading, 68)
                }

                if shownDirectory.isEmpty {
                    Text(
                        viewModel.isSearching
                            ? "No communities match your search."
                            : "No communities to show yet."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                }
            }
            .padding(.bottom, 24)
        }
    }

    /// When browsing, cap the directory so the landing stays snappy; when
    /// searching, show every match.
    private var shownDirectory: [CommunityListRow] {
        viewModel.isSearching ? viewModel.directory : Array(viewModel.directory.prefix(200))
    }

    private var signedOutNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(accent)
            Text("Browse freely — sign in to follow communities and get personal picks.")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var packsRail: some View {
        if !viewModel.starterPacks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Starter packs")
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    Text("Follow a curated bundle in one move")
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.starterPacks) { pack in
                            PackCard(pack: pack, accent: accent) { viewModel.openPack(pack) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func rail(title: String, subtitle: String, rows: [CommunityListRow], momentum: Bool) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(rows) { row in
                            DiscoverTrendCard(
                                row: row,
                                accent: accent,
                                momentum: momentum,
                                onTap: { viewModel.open(row) },
                                followState: viewModel.followState(for: row),
                                onFollow: { viewModel.follow(row) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var instanceRail: some View {
        if !viewModel.instances.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse by instance")
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    Text("Explore a server's communities")
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(viewModel.instances) { instance in
                            InstanceCard(instance: instance, accent: accent) {
                                viewModel.openInstance(instance)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var directoryHeader: some View {
        HStack {
            Text("All communities")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
            Text(viewModel.sort.title)
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Directory row

struct DiscoverCommunityRow: View {
    let row: CommunityListRow
    let accent: Color
    let onTap: () -> Void
    /// When set and the row collapses same-name variants, tapping the "also on N
    /// servers" badge opens the compare sheet instead of the community.
    var onCompare: (() -> Void)?
    /// Inline Follow state; ignored unless `onFollow` is supplied.
    var followState: CommunityFollowState = .idle
    /// When set, a trailing Follow control replaces the disclosure chevron.
    var onFollow: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            CommunityHueIcon(name: row.name, title: row.displayName, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineLimit(1)
                if row.alsoOnServerCount > 0 {
                    alsoOnBadge
                }
            }
            Spacer(minLength: 0)
            if let onFollow {
                FollowButton(state: followState, accent: accent, action: onFollow)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var handle: String {
        "c/\(row.name)@\(row.instanceHost) · \(Self.compact(row.numberOfSubscribers)) · \(Self.compact(row.usersActiveWeek))/wk"
    }

    @ViewBuilder
    private var alsoOnBadge: some View {
        let badge = HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 9, weight: .semibold))
            Text("also on \(row.alsoOnServerCount) other servers · \(Self.compact(row.groupTotalSubscribers))")
                .font(.caption2.weight(.semibold))
            if onCompare != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(accent.opacity(0.12), in: Capsule())
        .padding(.top, 4)

        if let onCompare {
            badge
                .contentShape(Capsule())
                .onTapGesture { onCompare() }
        } else {
            badge
        }
    }

    static func compact(_ value: Int64) -> String {
        let n = Double(value)
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", n / 1_000_000)
        case 1000...:
            return String(format: "%.0fK", n / 1000)
        default:
            return "\(value)"
        }
    }
}

// MARK: - Rail card

struct DiscoverTrendCard: View {
    let row: CommunityListRow
    let accent: Color
    let momentum: Bool
    let onTap: () -> Void
    /// Inline Follow state; ignored unless `onFollow` is supplied.
    var followState: CommunityFollowState = .idle
    /// When set, a Follow control is shown at the foot of the card.
    var onFollow: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CommunityHueIcon(name: row.name, title: row.displayName, size: 42)
                Spacer(minLength: 0)
                if momentum {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("active")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12), in: Capsule())
                }
            }
            .padding(.bottom, 10)

            Text(row.displayName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
            Text("c/\(row.name)@\(row.instanceHost)")
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
                .lineLimit(1)
                .padding(.top, 2)
            Text("\(DiscoverCommunityRow.compact(row.numberOfSubscribers)) · \(DiscoverCommunityRow.compact(row.usersActiveWeek))/wk")
                .font(.caption2)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.top, 7)

            if let onFollow {
                FollowButton(state: followState, accent: accent, action: onFollow)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 11)
            }
        }
        .padding(13)
        .frame(width: 178, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onTap() }
    }
}

// MARK: - Instance card

/// A home-instance card for the "Browse by instance" rail. Letter-tile avatar
/// over the host plus a community/member summary.
struct InstanceCard: View {
    let instance: InstanceSummary
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CommunityHueIcon(name: instance.host, title: instance.host, size: 42)
                Spacer(minLength: 0)
                Image(systemName: "server.rack")
                    .font(.caption)
                    .foregroundStyle(accent)
            }
            .padding(.bottom, 10)

            Text(instance.host)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
            Text("\(instance.communityCount) communities")
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.top, 2)
            Text("\(DiscoverCommunityRow.compact(instance.totalSubscribers)) members · \(DiscoverCommunityRow.compact(instance.totalActiveWeek))/wk")
                .font(.caption2)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.top, 7)
        }
        .padding(13)
        .frame(width: 178, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onTap() }
    }
}

// MARK: - Follow control

/// Inline Follow pill used by the directory rows and rail cards. Reflects the
/// view model's per-community ``CommunityFollowState`` and routes taps to the
/// supplied action only while idle (in-flight and followed are non-interactive).
struct FollowButton: View {
    let state: CommunityFollowState
    let accent: Color
    let action: () -> Void

    var body: some View {
        content
            .contentShape(Capsule())
            .onTapGesture {
                if state == .idle { action() }
            }
            .animation(.easeInOut(duration: 0.15), value: state)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            pill(text: "Follow", systemImage: "plus", filled: true)
        case .inFlight:
            ProgressView()
                .controlSize(.small)
                .tint(accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
        case .following:
            pill(text: "Following", systemImage: "checkmark", filled: false)
        }
    }

    private func pill(text: String, systemImage: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(filled ? Color.white : accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(filled ? accent : accent.opacity(0.14), in: Capsule())
    }
}

// MARK: - Icon

/// A deterministic letter-tile placeholder, tinted by a stable hue derived from
/// the community name (mirrors the Subscriptions list's icon style).
struct CommunityHueIcon: View {
    let name: String
    let title: String
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28)
            .fill(Color(hue: hue / 360, saturation: 0.5, brightness: 0.6))
            .frame(width: size, height: size)
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var letter: String {
        (title.first ?? name.first).map { String($0).uppercased() } ?? "?"
    }

    private var hue: Double {
        communityHue(name)
    }
}

// MARK: - Starter pack card

struct PackCard: View {
    let pack: ResolvedStarterPack
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                PackMosaic(communities: pack.communities, size: 52)
                Text(pack.title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .padding(.top, 11)
                Text(pack.blurb)
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
                    .frame(height: 30, alignment: .top)
                    .padding(.top, 3)
                Text("\(pack.communityCount) communities · \(DiscoverCommunityRow.compact(pack.totalSubscribers))")
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.top, 8)
            }
            .padding(14)
            .frame(width: 200, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// A 2x2 mosaic of hue tiles drawn from a pack's first communities.
struct PackMosaic: View {
    let communities: [CommunityListRow]
    var size: CGFloat = 52

    var body: some View {
        let hues = mosaicHues
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tile(hues[0])
                tile(hues[1])
            }
            HStack(spacing: 0) {
                tile(hues[2])
                tile(hues[3])
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }

    private var mosaicHues: [Double] {
        var hues = communities.prefix(4).map { communityHue($0.name) }
        while hues.count < 4 {
            hues.append(hues.first ?? 200)
        }
        return hues
    }

    private func tile(_ hue: Double) -> some View {
        Color(hue: hue / 360, saturation: 0.5, brightness: 0.6)
            .frame(width: size / 2, height: size / 2)
    }
}

/// Stable hue (0-360) from a community name, shared by the icon and the pack
/// mosaic so the same community always reads the same colour.
private func communityHue(_ name: String) -> Double {
    var hash: UInt64 = 5381
    for byte in name.utf8 {
        hash = (hash &* 33) &+ UInt64(byte)
    }
    return Double(hash % 360)
}
