//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Pure mapping of Explorer health/quality levels to colours, SF Symbols, and
/// compact strings. Shared by both instance-detail screens.
enum InstanceHealthStyle {
    static func color(for level: HealthLevel) -> UIColor {
        switch level {
        case .good: .systemGreen
        case .ok: .systemOrange
        case .bad: .systemRed
        case .unknown: .tertiaryLabel
        }
    }

    static func trustSymbol(_ level: HealthLevel) -> String {
        switch level {
        case .good: "checkmark.shield.fill"
        case .ok: "shield"
        case .bad: "exclamationmark.triangle.fill"
        case .unknown: "shield"
        }
    }

    static func registrationSymbol(_ mode: ExplorerRegistrationMode) -> String {
        switch mode {
        case .open: "globe"
        case .requireApplication: "doc.text"
        case .closed: "lock.fill"
        case .unknown: "globe"
        }
    }

    static func registrationShort(_ mode: ExplorerRegistrationMode) -> String {
        switch mode {
        case .open: "Open"
        case .requireApplication: "Apply"
        case .closed: "Closed"
        case .unknown: "—"
        }
    }

    /// Compact count (e.g. "1.2K", "32K"). Returns "—" for nil/zero.
    static func formatCount(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return CompactCount.string(value)
    }
}
