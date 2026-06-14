//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Sort order for the instance picker, over the Explorer directory.
public enum ExplorerInstanceSort: String, Sendable, CaseIterable {
    case recommended
    case users
    case activeUsers
    case uptime
    case name

    public var title: String {
        switch self {
        case .recommended: "Recommended"
        case .users: "Most users"
        case .activeUsers: "Most active"
        case .uptime: "Best uptime"
        case .name: "Name (A-Z)"
        }
    }
}

/// User-selected filters for the instance picker.
public struct ExplorerInstanceFilter: Sendable, Equatable {
    public var registrationOpenOnly: Bool
    public var hideNsfw: Bool
    /// Language code (e.g. "en"); nil means any language.
    public var language: String?

    public init(
        registrationOpenOnly: Bool = false,
        hideNsfw: Bool = false,
        language: String? = nil
    ) {
        self.registrationOpenOnly = registrationOpenOnly
        self.hideNsfw = hideNsfw
        self.language = language
    }

    public var isActive: Bool {
        registrationOpenOnly || hideNsfw || language != nil
    }
}

/// Pure filtering + sorting over instance picker rows. Lives in the data layer
/// (no UIKit) so it is unit-testable independently of the picker.
public enum ExplorerInstanceDirectory {
    /// Apply `filter`, free-text `query`, and `sort` to `rows`.
    public static func apply(
        to rows: [SiteListRow],
        query: String,
        filter: ExplorerInstanceFilter,
        sort: ExplorerInstanceSort
    ) -> [SiteListRow] {
        var result = rows

        if filter.registrationOpenOnly {
            result = result.filter(\.isOpenRegistration)
        }
        if filter.hideNsfw {
            result = result.filter { !$0.isNsfw }
        }
        if let language = filter.language {
            result = result.filter { $0.languageCodes.contains(language) }
        }

        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            result = result.filter { row in
                if row.hostname.lowercased().contains(needle) { return true }
                if let name = row.name?.lowercased(), name.contains(needle) { return true }
                if let description = row.descriptionText?.lowercased(), description.contains(needle) { return true }
                return false
            }
        }

        return result.sorted { lhs, rhs in ordered(lhs, before: rhs, by: sort) }
    }

    /// Distinct language codes present across `rows`, sorted, for building the
    /// language filter menu.
    public static func availableLanguages(in rows: [SiteListRow]) -> [String] {
        Set(rows.flatMap(\.languageCodes)).sorted()
    }

    private static func ordered(_ a: SiteListRow, before b: SiteListRow, by sort: ExplorerInstanceSort) -> Bool {
        switch sort {
        case .recommended:
            a.score > b.score
        case .users:
            (a.usersTotal ?? 0) > (b.usersTotal ?? 0)
        case .activeUsers:
            (a.usersActiveMonth ?? 0) > (b.usersActiveMonth ?? 0)
        case .uptime:
            (a.uptimeAllTime ?? -1) > (b.uptimeAllTime ?? -1)
        case .name:
            a.hostname.localizedCaseInsensitiveCompare(b.hostname) == .orderedAscending
        }
    }
}
