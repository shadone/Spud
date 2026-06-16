//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class FreshWashStateTests: XCTestCase {
    func testNotNewIsNone() {
        XCTAssertEqual(FreshWashState.resolve(isNew: false, hasAnimated: false, reduceMotion: false), .none)
        XCTAssertEqual(FreshWashState.resolve(isNew: false, hasAnimated: true, reduceMotion: true), .none)
    }

    func testReduceMotionNewIsStaticTint() {
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: false, reduceMotion: true), .staticTint)
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: true, reduceMotion: true), .staticTint)
    }

    func testNewNotYetAnimatedFadesFromTint() {
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: false, reduceMotion: false), .fadeFromTint)
    }

    func testNewAlreadyAnimatedIsNone() {
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: true, reduceMotion: false), .none)
    }
}
