//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUIKit

/// The True Black (OLED) theme was retired when the app adopted Liquid Glass.
/// A device that persisted it must degrade to the nearest equivalent rather
/// than silently resetting, which is what `UserDefaultsBacked` would otherwise
/// do on a decode failure.
struct AppThemeMigrationTests {
    @Test
    func legacyTrueBlackDecodesAsDark() throws {
        let data = Data(#""trueBlack""#.utf8)
        let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
        #expect(decoded == .dark)
    }

    @Test
    func liveCasesStillRoundTrip() throws {
        for theme in AppTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            #expect(try JSONDecoder().decode(AppTheme.self, from: data) == theme)
        }
    }

    @Test
    func unknownRawValueStillThrows() {
        let data = Data(#""notATheme""#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AppTheme.self, from: data)
        }
    }

    @Test
    func trueBlackIsNoLongerAnOfferedChoice() {
        #expect(AppTheme.allCases.count == 3)
        #expect(!AppTheme.allCases.map(\.rawValue).contains("trueBlack"))
    }
}
