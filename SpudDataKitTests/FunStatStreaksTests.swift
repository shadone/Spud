import Foundation
import Testing
@testable import SpudDataKit

struct FunStatStreaksTests {
    @Test
    func empty_isZero() {
        let result = FunStatStreaks.compute(activeDays: [], today: "2026-07-18")
        #expect(result.current == 0)
        #expect(result.longest == 0)
    }

    @Test
    func singleDayToday_isOneAndOne() {
        let result = FunStatStreaks.compute(activeDays: ["2026-07-18"], today: "2026-07-18")
        #expect(result.current == 1)
        #expect(result.longest == 1)
    }

    @Test
    func consecutiveRunEndingToday() {
        let result = FunStatStreaks.compute(
            activeDays: ["2026-07-15", "2026-07-16", "2026-07-17", "2026-07-18"],
            today: "2026-07-18"
        )
        #expect(result.current == 4)
        #expect(result.longest == 4)
    }

    @Test
    func runEndingYesterday_stillCountsAsCurrent() {
        // No activity yet today must not read as "streak broken".
        let result = FunStatStreaks.compute(
            activeDays: ["2026-07-16", "2026-07-17"],
            today: "2026-07-18"
        )
        #expect(result.current == 2)
        #expect(result.longest == 2)
    }

    @Test
    func gapBreaksCurrentButLongestSurvives() {
        let result = FunStatStreaks.compute(
            activeDays: ["2026-07-01", "2026-07-02", "2026-07-03", "2026-07-10", "2026-07-18"],
            today: "2026-07-18"
        )
        #expect(result.current == 1)
        #expect(result.longest == 3)
    }

    @Test
    func staleHistoryOnly_currentIsZero() {
        let result = FunStatStreaks.compute(
            activeDays: ["2026-07-01", "2026-07-02"],
            today: "2026-07-18"
        )
        #expect(result.current == 0)
        #expect(result.longest == 2)
    }

    @Test
    func monthBoundaryIsConsecutive() {
        let result = FunStatStreaks.compute(
            activeDays: ["2026-06-30", "2026-07-01"],
            today: "2026-07-01"
        )
        #expect(result.current == 2)
        #expect(result.longest == 2)
    }
}
