//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import ImageIO
import UIKit

/// Decodes multi-frame image data (GIF) into an animated `UIImage` using
/// ImageIO. A `UIImage` built with `animatedImage(with:duration:)` animates
/// automatically when assigned to a `UIImageView`.
public enum AnimatedImageDecoder {
    /// Builds an animated `UIImage` from `data`, or returns `nil` when the data
    /// is a single frame or cannot be decoded — callers fall back to a static
    /// `UIImage(data:)` in that case. Safe to call off the main thread.
    public static func animatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else { return nil }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        var totalDuration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            frames.append(UIImage(cgImage: cgImage))
            totalDuration += frameDelay(at: index, source: source)
        }

        guard frames.count > 1 else { return nil }
        if totalDuration <= 0 {
            // No usable per-frame delays; assume a typical 10fps playback.
            totalDuration = Double(frames.count) / 10.0
        }

        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }

    /// The display delay for the frame at `index`, mirroring the browser
    /// behaviour of clamping unreasonably short delays so GIFs do not play
    /// faster than intended.
    private static func frameDelay(at index: Int, source: CGImageSource) -> TimeInterval {
        let defaultDelay: TimeInterval = 0.1

        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return defaultDelay
        }

        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval
        let delay = unclamped ?? clamped ?? defaultDelay

        return delay < 0.011 ? defaultDelay : delay
    }
}
