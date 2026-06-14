//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension Preferences {
    /// How often the app automatically refreshes the bundled Lemmy Explorer
    /// directory (communities + instances) from data.lemmyverse.net, checked at
    /// launch. The matching `timeInterval` is used as the staleness threshold.
    enum ExplorerRefreshInterval: String, RawRepresentable, Codable, CaseIterable, Identifiable {
        case daily
        case everyThreeDays
        case weekly
        case monthly

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .daily: "Daily"
            case .everyThreeDays: "Every 3 Days"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            }
        }

        var timeInterval: TimeInterval {
            let day: TimeInterval = 86400
            switch self {
            case .daily: return day
            case .everyThreeDays: return 3 * day
            case .weekly: return 7 * day
            case .monthly: return 30 * day
            }
        }
    }
}
