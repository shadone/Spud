import Foundation
import Testing
import UIKit
@testable import Spud

struct AdaptiveLayoutTests {
    @Test
    func bannerDownsampleWidth_capsToDefault() {
        #expect(AdaptiveLayout.bannerDownsampleWidth(screenWidth: 1366) == 600)
        #expect(AdaptiveLayout.bannerDownsampleWidth(screenWidth: 390) == 390)
    }
}
