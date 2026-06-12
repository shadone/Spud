//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import ImageIO
import UIKit

/// Decodes image data directly at a reduced size using ImageIO, so a small cell
/// (e.g. a 64pt feed thumbnail) never holds a full-resolution bitmap in memory.
/// `CGImageSourceCreateThumbnailAtIndex` decodes straight to the target size,
/// which is both cheaper and far lighter than decoding full-size and scaling.
public enum ImageDownsampler {
    /// Downsamples `data` so its longest side is at most `maxPixelSize` pixels.
    /// Returns `nil` if the data can't be decoded; callers fall back to a full
    /// decode. Safe to call off the main thread.
    public static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard maxPixelSize > 0 else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded()),
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
