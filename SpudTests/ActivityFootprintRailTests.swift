// SpudTests/ActivityFootprintRailTests.swift
import Testing
@testable import Spud
@testable import SpudDataKit

struct ActivityFootprintRailTests {
    private let def: Set<ActivityFilterType> = [.post, .comment, .save]

    @Test
    func visibleInDefaultGlanceState() {
        #expect(ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: def, defaultFilters: def,
            hasSearchQuery: false, hasContent: true
        ))
    }

    @Test
    func hiddenWhenSummaryPinned() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: true, activeFilters: def, defaultFilters: def,
            hasSearchQuery: false, hasContent: true
        ))
    }

    @Test
    func hiddenWhenFiltersNonDefault() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: [.comment], defaultFilters: def,
            hasSearchQuery: false, hasContent: true
        ))
    }

    @Test
    func hiddenWhileSearching() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: def, defaultFilters: def,
            hasSearchQuery: true, hasContent: true
        ))
    }

    @Test
    func hiddenWhenEmpty() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: def, defaultFilters: def,
            hasSearchQuery: false, hasContent: false
        ))
    }

    @Test
    func footprintStatEquates() {
        #expect(FootprintStat(value: "12", label: "Posts") == FootprintStat(value: "12", label: "Posts"))
    }
}
