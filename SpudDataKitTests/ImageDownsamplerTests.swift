//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudDataKit

final class ImageDownsamplerTests: XCTestCase {
    /// PNG bytes for a solid-colour image of the given pixel size (scale 1).
    private func imageData(width: CGFloat, height: CGFloat) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.pngData())
    }

    func test_downsample_capsLongestSideToMaxPixelSize() throws {
        let data = try imageData(width: 600, height: 300)
        let image = try XCTUnwrap(ImageDownsampler.downsample(data: data, maxPixelSize: 100))
        let longestSidePixels = max(image.size.width, image.size.height) * image.scale
        XCTAssertLessThanOrEqual(longestSidePixels, 100, "longest side should be capped at maxPixelSize")
        XCTAssertGreaterThan(longestSidePixels, 0)
    }

    func test_downsample_preservesAspectRatio() throws {
        let data = try imageData(width: 600, height: 300)
        let image = try XCTUnwrap(ImageDownsampler.downsample(data: data, maxPixelSize: 100))
        // 2:1 source -> 2:1 result.
        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.1)
    }

    func test_downsample_nonImageData_returnsNil() {
        XCTAssertNil(ImageDownsampler.downsample(data: Data("not an image".utf8), maxPixelSize: 100))
    }

    func test_downsample_zeroMaxPixelSize_returnsNil() throws {
        let data = try imageData(width: 100, height: 100)
        XCTAssertNil(ImageDownsampler.downsample(data: data, maxPixelSize: 0))
    }
}
