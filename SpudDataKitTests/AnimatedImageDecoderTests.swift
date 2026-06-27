//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import SpudDataKit

struct AnimatedImageDecoderTests {
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
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test
    func multiFrameGif_decodesToAnimatedImage() {
        let image = AnimatedImageDecoder.animatedImage(from: makeGifData(frameCount: 3, delay: 0.2))
        #expect(image != nil)
        #expect(image?.images?.count == 3)
        #expect(abs((image?.duration ?? 0) - 0.6) <= 0.05)
    }

    @Test
    func singleFrameGif_returnsNil() {
        #expect(
            AnimatedImageDecoder.animatedImage(from: makeGifData(frameCount: 1)) == nil,
            "a single-frame image is not animated"
        )
    }

    @Test
    func nonImageData_returnsNil() {
        #expect(AnimatedImageDecoder.animatedImage(from: Data("not an image".utf8)) == nil)
    }
}
