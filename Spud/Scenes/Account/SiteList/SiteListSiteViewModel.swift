//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit
import SpudUtilKit
import UIKit

@MainActor
@Observable
final class SiteListSiteViewModel {
    typealias OwnDependencies =
        HasImageService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies

    @ObservationIgnored
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    let row: SiteListRow
    let title: AttributedString
    let descriptionText: AttributedString
    /// Compact, muted stats line surfacing the metrics the picker can sort by
    /// (total users, monthly active, all-time uptime). Empty when none are known.
    let statsText: AttributedString

    var iconState: ImageLoadingState?

    @ObservationIgnored
    private var iconFetchTask: Task<Void, Never>?

    init(row: SiteListRow, dependencies: Dependencies) {
        self.row = row
        self.dependencies = (own: dependencies, nested: dependencies)

        title = AttributedString(row.hostname, attributes: .init([
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2, weight: .medium),
            .foregroundColor: UIColor.label,
        ]))
        descriptionText = AttributedString(row.descriptionText ?? "", attributes: .init([
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 2, weight: .regular),
            .foregroundColor: UIColor.label,
        ]))
        statsText = AttributedString(Self.statsString(for: row), attributes: .init([
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 3, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
        ]))

        if let iconUrl = row.iconUrl {
            let stream = imageService.fetch(iconUrl)
            iconFetchTask = Task { [weak self] in
                for await state in stream {
                    guard let self else { return }
                    iconState = state
                }
            }
        } else {
            iconState = nil
        }
    }

    deinit {
        iconFetchTask?.cancel()
    }

    // MARK: - Stats formatting

    /// Builds the compact stats line, e.g. "12.3K users · 1.9K active · 99% uptime".
    /// Each component is omitted when its value is nil — never shown as "0" or "nil".
    /// `uptimeAllTime` is a 0...100 percentage (see `ExplorerInstanceRecord`),
    /// rendered as a whole-number percent.
    private static func statsString(for row: SiteListRow) -> String {
        var parts: [String] = []
        if let users = row.usersTotal {
            parts.append("\(abbreviatedCount(users)) users")
        }
        if let active = row.usersActiveMonth {
            parts.append("\(abbreviatedCount(active)) active")
        }
        if let uptime = row.uptimeAllTime {
            parts.append("\(Int(uptime.rounded()))% uptime")
        }
        return parts.joined(separator: " · ")
    }

    /// Compact K/M abbreviation (e.g. 12300 -> "12.3K").
    private static func abbreviatedCount(_ value: Int64) -> String {
        CountFormatter.string(value)
    }
}
