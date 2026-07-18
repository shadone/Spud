import Foundation
import Testing
@testable import Spud

struct FunEquivalenceTests {
    @Test
    func belowSmallestLandmark_isNil() {
        #expect(FunEquivalence.phrase(forMeters: 90) == nil)
    }

    @Test
    func picksLargestLandmarkPassed() throws {
        // 2000 m: past Eiffel (330) and Burj (828), short of Everest (8849).
        let phrase = try #require(FunEquivalence.phrase(forMeters: 2000))
        #expect(phrase.contains("Burj Khalifa"))
        #expect(phrase.contains("2.4x"))
    }

    @Test
    func exactMultipleFormatsWithoutTrailingDecimal() throws {
        let phrase = try #require(FunEquivalence.phrase(forMeters: 828 * 3))
        #expect(phrase.contains("3x"))
        #expect(!phrase.contains("3.0x"))
    }
}
