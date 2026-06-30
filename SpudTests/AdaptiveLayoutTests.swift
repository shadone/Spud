import Foundation
import Testing
import UIKit
@testable import Spud

struct AdaptiveLayoutTests {
    @Test
    func cappedContentWidth_capsWideCanvas() {
        #expect(AdaptiveLayout.cappedContentWidth(available: 1024, max: 600) == 600)
    }

    @Test
    func cappedContentWidth_passesThroughNarrow() {
        #expect(AdaptiveLayout.cappedContentWidth(available: 390, max: 600) == 390)
    }

    @Test
    func bannerDownsampleWidth_capsToDefault() {
        #expect(AdaptiveLayout.bannerDownsampleWidth(screenWidth: 1366) == 600)
        #expect(AdaptiveLayout.bannerDownsampleWidth(screenWidth: 390) == 390)
    }

    @Test
    func modalPresentationStyle_popoverOnRegular_sheetOnCompact() {
        #expect(AdaptiveLayout.modalPresentationStyle(for: .regular) == .popover)
        #expect(AdaptiveLayout.modalPresentationStyle(for: .compact) == .pageSheet)
        #expect(AdaptiveLayout.modalPresentationStyle(for: .unspecified) == .pageSheet)
    }
}
