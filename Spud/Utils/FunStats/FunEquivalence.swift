//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Real-world comparisons for the scroll-distance hero
/// ("That is 2.4x the height of Burj Khalifa").
enum FunEquivalence {
    struct Landmark {
        let name: String
        let meters: Double
    }

    /// Ascending by size; `phrase` picks the largest one already passed.
    static let landmarks: [Landmark] = [
        Landmark(name: "the Eiffel Tower", meters: 330),
        Landmark(name: "Burj Khalifa", meters: 828),
        Landmark(name: "Mount Everest", meters: 8849),
        Landmark(name: "the Mariana Trench", meters: 10935),
        Landmark(name: "the Karman line, the edge of space", meters: 100_000),
        Landmark(name: "the ISS orbit altitude", meters: 408_000),
    ]

    static func phrase(forMeters meters: Double) -> String? {
        guard let landmark = landmarks.last(where: { meters >= $0.meters }) else {
            return nil
        }
        let multiple = meters / landmark.meters
        let rounded = (multiple * 10).rounded() / 10
        let multipleText = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return "That is \(multipleText)x the height of \(landmark.name)"
    }
}
