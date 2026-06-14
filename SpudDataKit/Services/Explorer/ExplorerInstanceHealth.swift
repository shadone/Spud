//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Quality level for an instance health signal. Maps to a colour in the UI
/// (good = green, ok = orange, bad = red, unknown = tertiary).
public enum HealthLevel: String, Sendable, Equatable {
    case good
    case ok
    case bad
    case unknown
}

/// A single assessed health signal: a level plus a long and short label.
public struct HealthSignal: Sendable, Equatable {
    public let level: HealthLevel
    public let label: String
    public let short: String

    public init(level: HealthLevel, label: String, short: String) {
        self.level = level
        self.label = label
        self.short = short
    }
}

/// Pure health/quality assessment for an Explorer instance. Every signal
/// degrades to `.unknown` on missing data — never a guess or a fake zero.
/// Ported from the Spud Design instance-detail kit (feature #4).
public enum ExplorerInstanceHealth {
    /// Latest known Lemmy release, for version-freshness comparison. Bump per
    /// Lemmy release (or wire to a live value later).
    public static let latestLemmyVersion = "0.19.5"

    public static func uptime(_ value: Double?) -> HealthSignal {
        guard let value else {
            return HealthSignal(level: .unknown, label: "Uptime unknown", short: "—")
        }
        let level: HealthLevel = value >= 99 ? .good : value >= 95 ? .ok : .bad
        let percent = formatPercent(value)
        return HealthSignal(level: level, label: "\(percent) uptime", short: percent)
    }

    public static func version(_ value: String?, latest: String = latestLemmyVersion) -> HealthSignal {
        guard let value, !value.isEmpty else {
            return HealthSignal(level: .unknown, label: "Version unknown", short: "—")
        }
        let behind = minorValue(latest) - minorValue(value)
        let level: HealthLevel = behind <= 0 ? .good : behind == 1 ? .ok : .bad
        let suffix = level == .good ? "latest" : level == .ok ? "1 behind" : "outdated"
        return HealthSignal(level: level, label: "v\(value) · \(suffix)", short: "v\(value)")
    }

    public struct RegistrationAssessment: Sendable, Equatable {
        public let level: HealthLevel
        public let label: String
        public let canCreateAccount: Bool
    }

    public static func registration(_ mode: ExplorerRegistrationMode) -> RegistrationAssessment {
        switch mode {
        case .open: RegistrationAssessment(level: .good, label: "Open signups", canCreateAccount: true)
        case .requireApplication: RegistrationAssessment(level: .ok, label: "Application required", canCreateAccount: true)
        case .closed: RegistrationAssessment(level: .bad, label: "Signups closed", canCreateAccount: false)
        case .unknown: RegistrationAssessment(level: .unknown, label: "Unknown", canCreateAccount: false)
        }
    }

    /// `score100` is the Explorer score normalised to 0...100 (the stored score
    /// is 0...1; callers multiply by 100). A `suspicious` instance is always low
    /// trust regardless of score.
    public static func trust(score100: Double?, suspicious: Bool) -> HealthSignal {
        if suspicious {
            return HealthSignal(level: .bad, label: "Low trust", short: "Low trust")
        }
        guard let score100 else {
            return HealthSignal(level: .unknown, label: "Unrated", short: "Unrated")
        }
        let level: HealthLevel = score100 >= 75 ? .good : score100 >= 45 ? .ok : .bad
        let label = score100 >= 75 ? "Trusted" : score100 >= 45 ? "Mixed signals" : "Low trust"
        return HealthSignal(level: level, label: label, short: label)
    }

    // MARK: - Private

    /// Semver-ish "minor" distance: major * 1000 + minor.
    private static func minorValue(_ version: String) -> Int {
        let parts = version.split(separator: ".")
        let major = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return major * 1000 + minor
    }

    private static func formatPercent(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }
}
