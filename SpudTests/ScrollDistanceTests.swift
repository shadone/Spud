import Foundation
import Testing
@testable import Spud

struct ScrollDistanceTests {
    @Test
    func metersFromPoints_usesTheDocumentedConstant() {
        // 1 pt = 1/163 inch; 163 000 pt = 1000 inches = 25.4 m.
        let meters = ScrollDistance.meters(fromPoints: 163_000)
        #expect(abs(meters - 25.4) < 0.001)
    }

    @Test
    func displayString_metersUnderOneKilometer() {
        let text = ScrollDistance.displayString(meters: 42.4, locale: Locale(identifier: "en_US"))
        #expect(text == "42 m")
    }

    @Test
    func displayString_kilometers() {
        let text = ScrollDistance.displayString(meters: 12345, locale: Locale(identifier: "en_US"))
        #expect(text == "12.3 km")
    }

    @Test
    func displayString_roundingBoundary_999_4_meters() {
        let text = ScrollDistance.displayString(meters: 999.4, locale: Locale(identifier: "en_US"))
        #expect(text == "999 m")
    }

    @Test
    func displayString_roundingBoundary_999_5_meters() {
        let text = ScrollDistance.displayString(meters: 999.5, locale: Locale(identifier: "en_US"))
        #expect(text == "1 km")
    }
}
