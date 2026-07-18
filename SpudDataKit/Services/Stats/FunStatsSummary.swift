import Foundation

/// Read-model for the Fun Stats screen: lifetime totals plus derived
/// streak/rhythm facts. Produced by `AppDatabase.funStatsSummarySync` /
/// `observeFunStatsSummary`.
public struct FunStatsSummary: Sendable, Equatable {
    /// Lifetime SUM(value) per counter. Missing keys mean zero.
    public let totals: [FunStatKey: Double]
    /// Earliest recorded day ("yyyy-MM-dd"), nil when no data exists.
    public let firstDay: String?
    /// Consecutive active days ending today or yesterday.
    public let currentStreakDays: Int
    public let longestStreakDays: Int
    /// Local hour (0-23) with the largest event sum, nil when no data.
    public let mostActiveHour: Int?

    public init(
        totals: [FunStatKey: Double],
        firstDay: String?,
        currentStreakDays: Int,
        longestStreakDays: Int,
        mostActiveHour: Int?
    ) {
        self.totals = totals
        self.firstDay = firstDay
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.mostActiveHour = mostActiveHour
    }

    public func total(_ key: FunStatKey) -> Double {
        totals[key] ?? 0
    }
}
