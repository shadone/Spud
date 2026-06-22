//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import XCTest
@testable import Spud

final class FeedStatePresenterTests: XCTestCase {
    func testOfflineDescriptor() {
        let d = FeedStatePresenter.descriptor(for: .offline, host: "lemmy.world")
        XCTAssertEqual(d.symbolName, "wifi.slash")
        XCTAssertEqual(d.title, "You're offline")
        XCTAssertEqual(d.primary.action, .retry)
        XCTAssertNil(d.secondary)
    }

    func testUnreachableDescriptorInterpolatesHost() {
        let d = FeedStatePresenter.descriptor(for: .unreachable, host: "lemmy.world")
        XCTAssertEqual(d.symbolName, "globe")
        XCTAssertEqual(d.title, "Couldn't reach lemmy.world")
        XCTAssertEqual(d.primary.action, .retry)
        XCTAssertEqual(d.secondary?.action, .workOffline)
    }

    func testUnreachableFallsBackWhenHostNil() {
        let d = FeedStatePresenter.descriptor(for: .unreachable, host: nil)
        XCTAssertEqual(d.title, "Couldn't reach the server")
    }

    func testMalformedDescriptorOffersCopyDetails() {
        let d = FeedStatePresenter.descriptor(for: .malformedResponse, host: "lemmy.world")
        XCTAssertEqual(d.symbolName, "exclamationmark.triangle")
        XCTAssertEqual(d.title, "Something went wrong")
        XCTAssertEqual(d.primary.action, .retry)
        XCTAssertEqual(d.secondary?.action, .copyDetails)
    }
}
