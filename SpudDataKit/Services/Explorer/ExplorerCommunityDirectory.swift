//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Sort order for the community directory ("All communities") on Discover.
public enum ExplorerCommunitySort: String, Sendable, CaseIterable {
    case recommended
    case mostActive
    case members
    case name

    public var title: String {
        switch self {
        case .recommended: "Recommended"
        case .mostActive: "Most active"
        case .members: "Members"
        case .name: "Name (A-Z)"
        }
    }
}

/// User-selected filters for the community directory.
public struct ExplorerCommunityFilter: Sendable, Equatable {
    public var hideNsfw: Bool
    public var hideSuspicious: Bool

    public init(hideNsfw: Bool = false, hideSuspicious: Bool = false) {
        self.hideNsfw = hideNsfw
        self.hideSuspicious = hideSuspicious
    }
}

/// Pure ranking, filtering, search and same-name de-duplication over community
/// directory rows. Lives in the data layer (no UIKit) so every discovery rule is
/// unit-testable independently of the screens. All rankings come from the
/// directory's current snapshot (cumulative counts plus active-user windows);
/// there is no time series, no network, and no LLM.
public enum ExplorerCommunityDirectory {
    /// Noise floor for the Trending rail — communities with fewer recent active
    /// users than this are too quiet to be "trending".
    public static let defaultTrendingMinActiveWeek: Int64 = 50
    /// Size ceiling for the Rising rail — only communities at or below this many
    /// subscribers qualify as "small".
    public static let defaultRisingMaxSubscribers: Int64 = 25000
    /// Activity floor for the Rising rail.
    public static let defaultRisingMinActiveWeek: Int64 = 100

    /// Apply `filter`, free-text `query`, optional same-name de-duplication, and
    /// `sort` to `rows`, in that order.
    public static func apply(
        to rows: [CommunityListRow],
        query: String,
        filter: ExplorerCommunityFilter,
        sort: ExplorerCommunitySort,
        dedupeSameName: Bool = true
    ) -> [CommunityListRow] {
        var result = rows

        if filter.hideNsfw {
            result = result.filter { !$0.isNsfw }
        }
        if filter.hideSuspicious {
            result = result.filter { !$0.isSuspicious }
        }

        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            result = result.filter { matches($0, needle) }
        }

        if dedupeSameName {
            result = collapseSameName(result)
        }

        return result.sorted { ordered($0, before: $1, by: sort) }
    }

    /// The Trending rail: busiest communities this week. Suspicious and NSFW
    /// communities are always excluded (curated surfaces stay clean), same-name
    /// communities collapse to their busiest server, and a noise floor drops the
    /// barely-active.
    public static func trending(
        in rows: [CommunityListRow],
        limit: Int = 20,
        minActiveWeek: Int64 = defaultTrendingMinActiveWeek
    ) -> [CommunityListRow] {
        let eligible = rows.filter { curatedSafe($0) && $0.usersActiveWeek >= minActiveWeek }
        let collapsed = collapseSameName(eligible)
        return Array(collapsed.sorted { $0.usersActiveWeek > $1.usersActiveWeek }.prefix(limit))
    }

    /// The Rising rail: small communities with an outsized share of activity for
    /// their size. Suspicious and NSFW excluded, same-name collapsed.
    public static func rising(
        in rows: [CommunityListRow],
        limit: Int = 20,
        maxSubscribers: Int64 = defaultRisingMaxSubscribers,
        minActiveWeek: Int64 = defaultRisingMinActiveWeek
    ) -> [CommunityListRow] {
        let eligible = rows.filter {
            curatedSafe($0)
                && $0.numberOfSubscribers <= maxSubscribers
                && $0.usersActiveWeek >= minActiveWeek
        }
        let collapsed = collapseSameName(eligible)
        return Array(collapsed.sorted { engagement($0) > engagement($1) }.prefix(limit))
    }

    /// Every community sharing `name` across servers, ranked busiest-first, for
    /// the same-name compare sheet. Not de-duplicated.
    public static func variants(of name: String, in rows: [CommunityListRow]) -> [CommunityListRow] {
        let key = name.lowercased()
        return rows
            .filter { $0.name.lowercased() == key }
            .sorted(by: busier)
    }

    // MARK: - Helpers

    private static func curatedSafe(_ row: CommunityListRow) -> Bool {
        !row.isSuspicious && !row.isNsfw
    }

    private static func matches(_ row: CommunityListRow, _ needle: String) -> Bool {
        if row.name.lowercased().contains(needle) { return true }
        if let title = row.title?.lowercased(), title.contains(needle) { return true }
        if row.instanceHost.lowercased().contains(needle) { return true }
        if let description = row.descriptionText?.lowercased(), description.contains(needle) { return true }
        return false
    }

    /// Engagement intensity — recent activity relative to subscriber base.
    private static func engagement(_ row: CommunityListRow) -> Double {
        Double(row.usersActiveWeek) / Double(max(row.numberOfSubscribers, 1)).squareRoot()
    }

    /// Strict ordering used to pick the canonical (representative) variant within
    /// a same-name group: busiest server first, then largest, then best score,
    /// then host name for determinism.
    private static func busier(_ a: CommunityListRow, _ b: CommunityListRow) -> Bool {
        if a.usersActiveWeek != b.usersActiveWeek { return a.usersActiveWeek > b.usersActiveWeek }
        if a.numberOfSubscribers != b.numberOfSubscribers { return a.numberOfSubscribers > b.numberOfSubscribers }
        if a.score != b.score { return a.score > b.score }
        return a.instanceHost.localizedCaseInsensitiveCompare(b.instanceHost) == .orderedAscending
    }

    /// Collapse communities that share a name across servers into one canonical
    /// row (the busiest), annotated with how many other servers carry it and the
    /// combined subscriber total.
    private static func collapseSameName(_ rows: [CommunityListRow]) -> [CommunityListRow] {
        var groups: [String: [CommunityListRow]] = [:]
        var order: [String] = []
        for row in rows {
            let key = row.name.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order.map { key in
            let variants = groups[key]!.sorted(by: busier)
            var canonical = variants[0]
            canonical.alsoOnServerCount = variants.count - 1
            canonical.groupTotalSubscribers = variants.reduce(0) { $0 + $1.numberOfSubscribers }
            return canonical
        }
    }

    private static func ordered(
        _ a: CommunityListRow,
        before b: CommunityListRow,
        by sort: ExplorerCommunitySort
    ) -> Bool {
        switch sort {
        case .recommended:
            a.score > b.score
        case .mostActive:
            a.usersActiveWeek > b.usersActiveWeek
        case .members:
            a.numberOfSubscribers > b.numberOfSubscribers
        case .name:
            a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }
}
