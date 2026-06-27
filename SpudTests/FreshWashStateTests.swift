//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct FreshWashStateTests {
    @Test
    func notNewIsNone() {
        #expect(FreshWashState.resolve(isNew: false, hasAnimated: false, reduceMotion: false) == .none)
        #expect(FreshWashState.resolve(isNew: false, hasAnimated: true, reduceMotion: true) == .none)
    }

    @Test
    func reduceMotionNewIsStaticTint() {
        #expect(FreshWashState.resolve(isNew: true, hasAnimated: false, reduceMotion: true) == .staticTint)
        #expect(FreshWashState.resolve(isNew: true, hasAnimated: true, reduceMotion: true) == .staticTint)
    }

    @Test
    func newNotYetAnimatedFadesFromTint() {
        #expect(FreshWashState.resolve(isNew: true, hasAnimated: false, reduceMotion: false) == .fadeFromTint)
    }

    @Test
    func newAlreadyAnimatedIsNone() {
        #expect(FreshWashState.resolve(isNew: true, hasAnimated: true, reduceMotion: false) == .none)
    }
}
