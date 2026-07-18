import CoreGraphics
import Testing
@testable import Spud

struct ScrollOdometerTests {
    private let content: CGFloat = 5000
    private let viewport: CGFloat = 800

    @Test
    func accumulatesAbsoluteDeltas() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 0, contentHeight: content, viewportHeight: viewport)
        sut.update(offsetY: 100, contentHeight: content, viewportHeight: viewport)
        sut.update(offsetY: 40, contentHeight: content, viewportHeight: viewport) // scrolled back up 60
        #expect(sut.take() == 160)
    }

    @Test
    func take_drainsTheAccumulator() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 0, contentHeight: content, viewportHeight: viewport)
        sut.update(offsetY: 100, contentHeight: content, viewportHeight: viewport)
        #expect(sut.take() == 100)
        #expect(sut.take() == 0)
    }

    @Test
    func firstUpdate_establishesBaselineWithoutCounting() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 2400, contentHeight: content, viewportHeight: viewport)
        #expect(sut.take() == 0)
    }

    @Test
    func rubberBandOvershoot_isClampedOut() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 0, contentHeight: content, viewportHeight: viewport)
        sut.update(offsetY: -120, contentHeight: content, viewportHeight: viewport) // top bounce
        sut.update(offsetY: 0, contentHeight: content, viewportHeight: viewport)
        #expect(sut.take() == 0)
    }

    @Test
    func programmaticJump_isNotCounted() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 4000, contentHeight: content, viewportHeight: viewport)
        // Restore/scroll-to-top style jump: larger than one viewport in a
        // single event. Resyncs the baseline without counting.
        sut.update(offsetY: 0, contentHeight: content, viewportHeight: viewport)
        sut.update(offsetY: 100, contentHeight: content, viewportHeight: viewport)
        #expect(sut.take() == 100)
    }

    @Test
    func reset_clearsBaselineAndAccumulator() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 0, contentHeight: content, viewportHeight: viewport)
        sut.update(offsetY: 100, contentHeight: content, viewportHeight: viewport)
        sut.reset()
        #expect(sut.take() == 0)
        sut.update(offsetY: 500, contentHeight: content, viewportHeight: viewport)
        #expect(sut.take() == 0) // first post-reset update is baseline only
    }

    @Test
    func contentShorterThanViewport_neverAccumulates() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 0, contentHeight: 400, viewportHeight: 800)
        sut.update(offsetY: -20, contentHeight: 400, viewportHeight: 800)
        sut.update(offsetY: 10, contentHeight: 400, viewportHeight: 800)
        #expect(sut.take() == 0)
    }

    @Test
    func jumpExactlyOneViewport_isCounted() {
        var sut = ScrollOdometer()
        sut.update(offsetY: 0, contentHeight: content, viewportHeight: viewport)
        sut.update(offsetY: viewport, contentHeight: content, viewportHeight: viewport)
        #expect(sut.take() == 800)
    }
}
