//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import SpudDataKit

final class AnimatedImageDecoderTests: XCTestCase {
    private func solidFrame(_ color: UIColor) -> CGImage {
        let size = CGSize(width: 4, height: 4)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.cgImage!
    }

    /// Encodes a GIF with `frameCount` frames, each held for `delay` seconds.
    private func makeGifData(frameCount: Int, delay: Double = 0.1) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frameCount, nil
        )!
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        let palette: [UIColor] = [.red, .green, .blue, .yellow]
        for index in 0..<frameCount {
            CGImageDestinationAddImage(destination, solidFrame(palette[index % palette.count]), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay],
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func test_multiFrameGif_decodesToAnimatedImage() {
        let image = AnimatedImageDecoder.animatedImage(from: makeGifData(frameCount: 3, delay: 0.2))
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.images?.count, 3)
        XCTAssertEqual(image?.duration ?? 0, 0.6, accuracy: 0.05)
    }

    func test_singleFrameGif_returnsNil() {
        XCTAssertNil(
            AnimatedImageDecoder.animatedImage(from: makeGifData(frameCount: 1)),
            "a single-frame image is not animated"
        )
    }

    func test_nonImageData_returnsNil() {
        XCTAssertNil(AnimatedImageDecoder.animatedImage(from: Data("not an image".utf8)))
    }
}
