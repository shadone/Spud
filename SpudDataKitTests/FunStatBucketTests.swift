import Foundation
import Testing
@testable import SpudDataKit

struct FunStatBucketTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test
    func make_formatsDayAndHourInGivenCalendar() {
        // 2026-07-18 21:35:00 UTC
        let date = Date(timeIntervalSince1970: 1_784_410_500)
        let bucket = FunStatBucket.make(date: date, calendar: utc)
        #expect(bucket.day == "2026-07-18")
        #expect(bucket.hour == 21)
    }

    @Test
    func make_respectsTimeZone() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 2026-07-18 21:35 UTC == 2026-07-19 06:35 in Tokyo
        let date = Date(timeIntervalSince1970: 1_784_410_500)
        let bucket = FunStatBucket.make(date: date, calendar: tokyo)
        #expect(bucket.day == "2026-07-19")
        #expect(bucket.hour == 6)
    }
}
