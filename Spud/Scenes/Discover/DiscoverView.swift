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
    let viewModel: DiscoverViewModel
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
                }

                directoryHeader

                ForEach(shownDirectory) { row in
                    DiscoverCommunityRow(row: row, accent: accent) { viewModel.open(row) }
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
                            DiscoverTrendCard(row: row, accent: accent, momentum: momentum) {
                                viewModel.open(row)
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

    var body: some View {
        Button(action: onTap) {
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var handle: String {
        "c/\(row.name)@\(row.instanceHost) · \(Self.compact(row.numberOfSubscribers)) · \(Self.compact(row.usersActiveWeek))/wk"
    }

    private var alsoOnBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 9, weight: .semibold))
            Text("also on \(row.alsoOnServerCount) other servers · \(Self.compact(row.groupTotalSubscribers))")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(accent.opacity(0.12), in: Capsule())
        .padding(.top, 4)
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

    var body: some View {
        Button(action: onTap) {
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
            }
            .padding(13)
            .frame(width: 178, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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
        var h: UInt64 = 5381
        for byte in name.utf8 {
            h = (h &* 33) &+ UInt64(byte)
        }
        return Double(h % 360)
    }
}
