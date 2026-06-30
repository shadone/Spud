// Spud/Scenes/Activity/ActivityFootprintRail.swift
import Foundation
import SpudDataKit

/// One quick stat shown in the footprint rail (mirrors a Summary stat tile).
struct FootprintStat: Equatable {
    let value: String
    let label: String
}

/// Pure visibility rule for the iPhone "Your footprint" rail. Kept UIKit-free
/// so the rule is unit-testable. The rail is a default-state glance only; it is
/// suppressed on iPad where the Summary is pinned in the detail column.
enum ActivityFootprintRail {
    static func isVisible(
        summaryIsPinned: Bool,
        activeFilters: Set<ActivityFilterType>,
        defaultFilters: Set<ActivityFilterType>,
        hasSearchQuery: Bool,
        hasContent: Bool
    ) -> Bool {
        guard !summaryIsPinned else { return false }
        guard activeFilters == defaultFilters else { return false }
        guard !hasSearchQuery else { return false }
        return hasContent
    }
}
