//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Synthesizes deterministic placeholder images for the Lab so the renderer's
/// loaded image state can be eyeballed offline. The hue is derived from the URL
/// so distinct images look distinct (a stable, per-launch-consistent sum of
/// scalar values — not `hashValue`, which is seeded per process).
enum LabImageFactory {
    static func placeholder(for url: URL) -> UIImage {
        let size = CGSize(width: 480, height: 300)
        let seed = url.absoluteString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = CGFloat(seed % 360) / 360
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let top = UIColor(hue: hue, saturation: 0.5, brightness: 0.85, alpha: 1)
            let bottom = UIColor(hue: hue, saturation: 0.6, brightness: 0.5, alpha: 1)
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(
                colorsSpace: space,
                colors: [top.cgColor, bottom.cgColor] as CFArray,
                locations: [0, 1]
            ) else {
                top.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                return
            }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }
}
