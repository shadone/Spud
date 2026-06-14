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
        let current = components(value)
        let newest = components(latest)
        let level: HealthLevel
        let suffix: String
        if rank(current) >= rank(newest) {
            // Up to date, or a newer build than our reference — not penalised.
            level = .good
            suffix = "latest"
        } else if current.major == newest.major, current.minor == newest.minor {
            // Behind only on patch releases within the same minor series.
            level = .ok
            suffix = "\(newest.patch - current.patch) behind"
        } else {
            // A whole minor (or major) version behind.
            level = .bad
            suffix = "outdated"
        }
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

    /// Splits a "major.minor.patch" string into its numeric parts, defaulting
    /// missing or non-numeric parts to 0.
    private static func components(_ version: String) -> (major: Int, minor: Int, patch: Int) {
        let parts = version.split(separator: ".")
        func part(_ index: Int) -> Int {
            parts.count > index ? Int(parts[index]) ?? 0 : 0
        }
        return (part(0), part(1), part(2))
    }

    /// Orders a version for comparison. Patch-aware (unlike a minor-only
    /// compare), so an instance a single patch behind is distinguishable from
    /// the latest release.
    private static func rank(_ version: (major: Int, minor: Int, patch: Int)) -> Int {
        version.major * 1_000_000 + version.minor * 1000 + version.patch
    }

    private static func formatPercent(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }
}
