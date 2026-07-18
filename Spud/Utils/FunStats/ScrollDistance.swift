//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Point-to-distance conversion for the scroll odometer.
enum ScrollDistance {
    /// 1 point = 1/163 inch (the classic 163 ppi baseline). Fun, not
    /// science: real point size varies per device; the constant is
    /// documented in the feature doc and applied uniformly.
    static let metersPerPoint: Double = 0.0254 / 163.0

    static func meters(fromPoints points: Double) -> Double {
        points * metersPerPoint
    }

    /// "42 m" below 1 km, "12.3 km" above. Fixed metric units so the hero
    /// number and the landmark equivalences share one scale.
    static func displayString(meters: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if meters < 1000 {
            formatter.maximumFractionDigits = 0
            let number = formatter.string(from: NSNumber(value: meters)) ?? "0"
            return "\(number) m"
        }
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        let number = formatter.string(from: NSNumber(value: meters / 1000)) ?? "0"
        return "\(number) km"
    }
}
