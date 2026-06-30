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

    /// Read from the environment (set by the hosting controller) only to pass it
    /// back into the presented compare sheet, which is a separate environment.
    @Environment(\.imageService) private var imageService
    /// Drives the compact vs. regular layout branch: horizontal carousels in
    /// compact (iPhone), adaptive grids + capped directory in regular (iPad).
    @Environment(\.horizontalSizeClass) private var hSizeClass

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
                viewModel: viewModel,
                target: target,
                accent: accent,
                onOpenCommunity: { viewModel.openFromCompare($0) },
                onDismiss: { viewModel.compareTarget = nil }
            )
            .environment(\.imageService, imageService)
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

                // In the regular size class (iPad) the directory column is capped
                // and centered so it does not stretch full-bleed across the wide
                // canvas. The 200-row cap on `shownDirectory` keeps this VStack
                // compact enough that the loss of per-row laziness is immaterial.
                VStack(spacing: 0) {
                    ForEach(shownDirectory) { row in
                        DiscoverCommunityRow(
                            row: row,
                            accent: accent,
                            onTap: { viewModel.open(row) },
                            onCompare: { viewModel.compare(row) },
                            subscriptionState: viewModel.subscriptionState(for: row),
                            onSubscribe: { viewModel.toggleSubscription(row) },
                            blurNsfw: viewModel.blurNsfw
                        )
                        .communityContextMenu(for: row, viewModel: viewModel)
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

                    if viewModel.isSearching {
                        networkSearchSection
                    }
                }
                .frame(maxWidth: hSizeClass == .regular ? AdaptiveLayout.directoryMaxWidth : .infinity)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var networkSearchSection: some View {
        switch viewModel.networkSearchPhase {
        case .idle:
            Button { viewModel.searchNetwork() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text("Search the network for “\(viewModel.searchText.trimmingCharacters(in: .whitespaces))”")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .padding(14)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)

        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching the network…")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)

        case .loaded:
            sectionHeader("From the network")
            if viewModel.networkResults.isEmpty {
                Text("No additional communities found on the network.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(viewModel.networkResults) { row in
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

        case .failed:
            Button { viewModel.searchNetwork() } label: {
                Text("Network search failed. Tap to retry.")
                    .font(.subheadline)
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
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
            Text("Browse freely — sign in to subscribe to communities and get personal picks.")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Shared rail header: title + subtitle, with an optional trailing "See all"
    /// that opens the rail's full ranked list. Passing `onSeeAll: nil` (e.g. for
    /// Starter packs, which has no overflow) omits the affordance.
    private func railHeader(title: String, subtitle: String, onSeeAll: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Spacer(minLength: 8)
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 2) {
                        Text("See all")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var packsRail: some View {
        if !viewModel.starterPacks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                railHeader(
                    title: "Starter packs",
                    subtitle: "Subscribe to a curated bundle in one move",
                    onSeeAll: nil
                )

                if hSizeClass == .regular {
                    // In the regular size class (iPad) show an adaptive grid so
                    // the wide canvas is used rather than wasting space beside a
                    // narrow horizontal strip.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 178), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.starterPacks) { pack in
                            PackCard(pack: pack, accent: accent) { viewModel.openPack(pack) }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
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
    }

    @ViewBuilder
    private func rail(title: String, subtitle: String, rows: [CommunityListRow], momentum: Bool) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                railHeader(
                    title: title,
                    subtitle: subtitle,
                    onSeeAll: rows.count > DiscoverViewModel.railCarouselCount
                        ? { viewModel.seeAllCommunities(title: title, rows: rows) }
                        : nil
                )

                if hSizeClass == .regular {
                    // In the regular size class (iPad) show an adaptive grid instead
                    // of a horizontal carousel so cards fill the wide canvas.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 178), spacing: 11)], spacing: 11) {
                        ForEach(rows.prefix(DiscoverViewModel.railCarouselCount)) { row in
                            DiscoverTrendCard(
                                row: row,
                                accent: accent,
                                momentum: momentum,
                                onTap: { viewModel.open(row) },
                                subscriptionState: viewModel.subscriptionState(for: row),
                                onSubscribe: { viewModel.toggleSubscription(row) },
                                blurNsfw: viewModel.blurNsfw
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 11) {
                            ForEach(rows.prefix(DiscoverViewModel.railCarouselCount)) { row in
                                DiscoverTrendCard(
                                    row: row,
                                    accent: accent,
                                    momentum: momentum,
                                    onTap: { viewModel.open(row) },
                                    subscriptionState: viewModel.subscriptionState(for: row),
                                    onSubscribe: { viewModel.toggleSubscription(row) },
                                    blurNsfw: viewModel.blurNsfw
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var instanceRail: some View {
        if !viewModel.instances.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                railHeader(
                    title: "Browse by instance",
                    subtitle: "Explore a server's communities",
                    onSeeAll: viewModel.instances.count > DiscoverViewModel.railCarouselCount
                        ? { viewModel.seeAllInstances() }
                        : nil
                )

                if hSizeClass == .regular {
                    // In the regular size class (iPad) show an adaptive grid.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 178), spacing: 11)], spacing: 11) {
                        ForEach(viewModel.instances.prefix(DiscoverViewModel.railCarouselCount)) { instance in
                            InstanceCard(instance: instance, accent: accent) {
                                viewModel.openInstance(instance)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 11) {
                            ForEach(viewModel.instances.prefix(DiscoverViewModel.railCarouselCount)) { instance in
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
        // Cap the directory header to the same width as the directory rows so
        // the text and sort label do not stretch full-bleed on a wide iPad canvas.
        .frame(maxWidth: hSizeClass == .regular ? AdaptiveLayout.directoryMaxWidth : .infinity)
        .frame(maxWidth: .infinity)
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
    /// Inline subscription state; ignored unless `onSubscribe` is supplied.
    var subscriptionState: CommunitySubscriptionState = .idle
    /// When set, a trailing Subscribe control replaces the disclosure chevron.
    var onSubscribe: (() -> Void)?
    /// Line limit for the handle subtitle. `1` truncates (Discover home / pack
    /// rows stay compact); pass `nil` to let it wrap, as the instance drill-in does.
    var subtitleLineLimit: Int? = 1
    /// When `false`, the handle drops the `c/` prefix and `@host` suffix, leaving the
    /// bare community name — used by the instance drill-in, where every row shares the
    /// same host shown in the header. Defaults to the fully qualified `c/name@host`.
    var showsQualifiedHandle: Bool = true
    /// When `true` and `row.isNsfw`, the community icon is obscured. Defaults to
    /// `false` so call sites outside Discover (instance drill-in) are unaffected.
    var blurNsfw: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            CommunityIcon(iconUrl: row.iconUrl, name: row.name, title: row.displayName, size: 40, isNsfwBlurred: row.isNsfw && blurNsfw)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                    if row.isNsfw {
                        NsfwBadge()
                    }
                }
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineLimit(subtitleLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                if row.alsoOnServerCount > 0 {
                    alsoOnBadge
                }
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
        .padding(.vertical, 10)
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
            if let onCompare {
                Button("Compare across servers", action: onCompare)
            }
        }
    }

    private var handle: String {
        let lead = showsQualifiedHandle ? "c/\(row.name)@\(row.instanceHost)" : row.name
        return "\(lead) · \(Self.compact(row.numberOfSubscribers)) · \(Self.compact(row.usersActiveWeek))/wk"
    }

    private var accessibilityLabel: String {
        var parts = [row.displayName, "c/\(row.name)@\(row.instanceHost)"]
        if row.isNsfw { parts.append("NSFW") }
        parts.append("\(Self.compact(row.numberOfSubscribers)) subscribers")
        if subscriptionState == .subscribed { parts.append("Subscribed") }
        if row.alsoOnServerCount > 0 { parts.append("also on \(row.alsoOnServerCount) other servers") }
        return parts.joined(separator: ", ")
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
    /// Inline subscription state; ignored unless `onSubscribe` is supplied.
    var subscriptionState: CommunitySubscriptionState = .idle
    /// When set, a Subscribe control is shown at the foot of the card.
    var onSubscribe: (() -> Void)?
    /// When `true` and `row.isNsfw`, the community icon is obscured.
    var blurNsfw: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CommunityIcon(iconUrl: row.iconUrl, name: row.name, title: row.displayName, size: 42, isNsfwBlurred: row.isNsfw && blurNsfw)
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

            if let onSubscribe {
                SubscribeButton(state: subscriptionState, accent: accent, action: onSubscribe)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 11)
            }
        }
        .padding(13)
        .frame(width: 178, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
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
        var parts = [
            row.displayName,
            "c/\(row.name)@\(row.instanceHost)",
            "\(DiscoverCommunityRow.compact(row.usersActiveWeek)) active this week",
        ]
        if subscriptionState == .subscribed { parts.append("Subscribed") }
        return parts.joined(separator: ", ")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(instance.host), \(instance.communityCount) communities")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }
}

// MARK: - Subscribe control

/// Inline Subscribe pill used by the directory rows and rail cards. Reflects the
/// view model's per-community ``CommunitySubscriptionState``; taps act unless a
/// request is in flight (idle subscribes, subscribed unsubscribes). When it sits
/// inside a combined-accessibility row the row exposes the action; this label/trait
/// covers any standalone use.
struct SubscribeButton: View {
    let state: CommunitySubscriptionState
    let accent: Color
    let action: () -> Void

    var body: some View {
        content
            .contentShape(Capsule())
            .onTapGesture {
                if state != .inFlight { action() }
            }
            .animation(.easeInOut(duration: 0.15), value: state)
            .accessibilityLabel(state == .subscribed ? "Unsubscribe" : "Subscribe")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            pill(text: "Subscribe", systemImage: "plus", filled: true)
        case .inFlight:
            ProgressView()
                .controlSize(.small)
                .tint(accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
        case .subscribed:
            pill(text: "Subscribed", systemImage: "checkmark", filled: false)
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
