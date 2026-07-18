//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Renders a laid-out share card view (``ShareCardView`` / ``ShareChainCardView``,
/// or any fixed-width card view) to a `UIImage`, writes it to a temporary PNG
/// with the alt text embedded as image metadata, and assembles the share-sheet
/// payload.
///
/// `@MainActor` because it drives the card view's layout pass and renders its
/// layer. The card views are built to render deterministically off-screen, so
/// no view needs to be on screen — the renderer runs the layout pass itself and
/// draws via `layer.render(in:)` (`drawHierarchy` requires an on-screen view).
///
/// Export scale is a fixed 3x (``exportScale``): a 372pt-wide card exports to a
/// 1116px-wide native PNG; the `.square` canvas to 1080x1080; the `.story`
/// canvas to 1080x1920.
@MainActor
enum ShareCardImageRenderer {
    /// The fixed pixel-per-point scale every export renders at. Not the device
    /// scale — a shared image must have the same resolution regardless of the
    /// capturing device.
    static let exportScale: CGFloat = 3

    /// The `.square` canvas design size in points (renders to 1080x1080 at 3x).
    static let squareCanvasSize = CGSize(width: 360, height: 360)
    /// The `.story` canvas design size in points (renders to 1080x1920 at 3x).
    static let storyCanvasSize = CGSize(width: 360, height: 640)
    /// Minimum breathing room between the card and the canvas edge in the
    /// backdrop canvases.
    static let minBackdropPadding: CGFloat = 30

    /// How old a leftover export subdirectory must be before ``sweepStaleExports(now:)``
    /// deletes it (24 hours). Each export writes into a fresh UUID subdirectory
    /// and otherwise relies on the OS to GC the temp dir; the sweep bounds the
    /// leftover footprint proactively without racing an in-flight share.
    /// `nonisolated` so the nonisolated ``sweepStaleExports(now:)`` can read it.
    nonisolated static let staleExportAge: TimeInterval = 24 * 60 * 60

    /// Errors from ``writePNG(_:altText:suggestedName:)``.
    enum RenderError: Error {
        /// The `UIImage` had no backing `CGImage` to encode.
        case missingCGImage
        /// `CGImageDestination` could not be created for the temp URL.
        case destinationCreationFailed
        /// `CGImageDestinationFinalize` returned false.
        case encodingFailed
    }

    // MARK: - Render

    /// Renders `cardView` to a `UIImage` per `options.canvas`:
    /// - `.native`: the image hugs the card (transparent outside its rounded
    ///   corners).
    /// - `.square` / `.story`: the card is centered on the decorative backdrop
    ///   (radial gradient + dot grid, following `options.appearance`), scaled
    ///   DOWN only to leave at least ``minBackdropPadding`` on every side —
    ///   never enlarged past its native size.
    ///
    /// The card's own layout pass runs first (pinned to the fixed design width),
    /// so the caller need not have laid the view out.
    static func render(cardView: UIView, options: ShareCardOptions) -> UIImage {
        let cardImage = renderCard(cardView)

        switch options.canvas {
        case .native:
            return cardImage
        case .square:
            return composite(cardImage: cardImage, canvasSize: squareCanvasSize, options: options)
        case .story:
            return composite(cardImage: cardImage, canvasSize: storyCanvasSize, options: options)
        }
    }

    /// Lays the card out at the fixed design width and renders its layer at
    /// ``exportScale``. Transparent outside the card so the rounded corners
    /// survive on the `.native` canvas and reveal the backdrop on the others.
    private static func renderCard(_ view: UIView) -> UIImage {
        let width = ShareCardMetrics.width

        // Solve for height at the fixed design width. A real card view resolves
        // its height from Auto Layout here; a degenerate view (no constraints)
        // falls back to whatever bounds height it already carries.
        let fitting = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = fitting.height > 1 ? fitting.height : max(view.bounds.height, 1)
        let size = CGSize(width: width, height: height)

        view.bounds = CGRect(origin: .zero, size: size)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        return image(size: size, opaque: false) { context in
            view.layer.render(in: context.cgContext)
        }
    }

    /// Composites the already-rendered `cardImage` centered on the backdrop.
    private static func composite(
        cardImage: UIImage,
        canvasSize: CGSize,
        options: ShareCardOptions
    ) -> UIImage {
        let palette = options.appearance.palette
        let cardRect = cardDrawRect(cardSize: cardImage.size, canvasSize: canvasSize)

        return image(size: canvasSize, opaque: true) { context in
            ShareCardBackdrop.draw(
                in: context.cgContext,
                rect: CGRect(origin: .zero, size: canvasSize),
                palette: palette
            )
            cardImage.draw(in: cardRect)
        }
    }

    /// The centered, scale-down-only rect for the card within the canvas.
    static func cardDrawRect(cardSize: CGSize, canvasSize: CGSize) -> CGRect {
        let availableWidth = canvasSize.width - 2 * minBackdropPadding
        let availableHeight = canvasSize.height - 2 * minBackdropPadding
        // Fit within the padded area, but never scale the card UP past 1:1.
        let scale = min(
            min(availableWidth / cardSize.width, availableHeight / cardSize.height),
            1
        )
        let drawSize = CGSize(width: cardSize.width * scale, height: cardSize.height * scale)
        let origin = CGPoint(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2
        )
        return CGRect(origin: origin, size: drawSize)
    }

    /// A `UIGraphicsImageRenderer` image pinned to ``exportScale``.
    private static func image(
        size: CGSize,
        opaque: Bool,
        _ actions: (UIGraphicsImageRendererContext) -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = exportScale
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: actions)
    }

    // MARK: - PNG + metadata

    /// Encodes `image` to a PNG in a fresh temporary subdirectory and embeds
    /// `altText` as image metadata so it travels with the file: the PNG
    /// `Description` text chunk AND the IPTC caption/abstract. Recipients and
    /// assistive tech that read either field then see the card's alt text.
    ///
    /// The filename derives from `suggestedName` (sanitized, `.png` extension),
    /// falling back to `"spud-share"` when nothing usable remains.
    ///
    /// `async` because the ImageIO encode + disk write (~2 MP) runs off the main
    /// actor via the `nonisolated` ``encodePNG(cgImage:altText:to:)`` helper: the
    /// only main-actor work here is extracting the backing `CGImage` from the
    /// `UIImage` and creating the destination directory. `CGImage` is `Sendable`
    /// (the SDK's own conformance, not one of ours), so it crosses into the
    /// off-actor encode with no `@unchecked` wrapper of our own. Callers already
    /// run inside a `Task`, so the hop is free.
    static func writePNG(_ image: UIImage, altText: String, suggestedName: String) async throws -> URL {
        // Best-effort: reclaim leftover export dirs before writing this one.
        sweepStaleExports()

        guard let cgImage = image.cgImage else {
            throw RenderError.missingCGImage
        }
        let fileURL = try makeExportFileURL(suggestedName: suggestedName)
        try await encodePNG(cgImage: cgImage, altText: altText, to: fileURL)
        return fileURL
    }

    /// Creates a fresh unique subdirectory under the shared export root and
    /// returns the sanitized `.png` file URL inside it.
    private static func makeExportFileURL(suggestedName: String) throws -> URL {
        let directory = shareRootDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent(sanitizedFileName(suggestedName))
            .appendingPathExtension("png")
    }

    /// Encodes `cgImage` to `fileURL` as a PNG with `altText` embedded as
    /// metadata. `nonisolated async` so it runs off the caller's (main) actor —
    /// the blocking ImageIO encode + disk write does not belong on the main
    /// thread. `CGImage` is `Sendable` (SDK conformance), so it crosses the
    /// isolation boundary here without any wrapper of ours.
    private nonisolated static func encodePNG(
        cgImage: CGImage,
        altText: String,
        to fileURL: URL
    ) async throws {
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RenderError.destinationCreationFailed
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: altText],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: altText],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw RenderError.encodingFailed
        }
    }

    // MARK: - Temp-dir sweep

    /// The root directory every export subdirectory nests under.
    nonisolated static var shareRootDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("share-as-image", isDirectory: true)
    }

    /// Best-effort deletion of leftover export subdirectories older than
    /// ``staleExportAge``. Never throws — a sweep failure must not block an
    /// export. `now` is injectable for tests. `nonisolated` (pure file I/O), so
    /// it can run off any actor; ``writePNG(_:altText:suggestedName:)`` calls it
    /// before creating the new subdir, so the just-created directory is never a
    /// sweep candidate.
    nonisolated static func sweepStaleExports(now: Date = Date()) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: shareRootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true, let modified = values?.contentModificationDate else { continue }
            if now.timeIntervalSince(modified) > staleExportAge {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    /// Turns an arbitrary suggested name into a safe filename stem: path
    /// separators and control characters become spaces, runs of whitespace
    /// collapse, the result is trimmed and capped, and an empty result falls
    /// back to `"spud-share"`. `nonisolated` — it is pure string work.
    nonisolated static func sanitizedFileName(_ name: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:")
            .union(.controlCharacters)
            .union(.newlines)
        let replaced = name.components(separatedBy: disallowed).joined(separator: " ")
        let collapsed = replaced.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(80)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? "spud-share" : capped
    }

    // MARK: - Share payload

    /// The share-sheet activity items: the PNG file URL first (it carries the
    /// embedded alt-text/caption metadata that a bare `UIImage` item would
    /// strip), then the permalink so the share also links back to the source.
    ///
    /// `image` is accepted for call-site symmetry with the render/write pair but
    /// intentionally not shared as its own item — the metadata-bearing file is
    /// the canonical image payload.
    static func shareItems(image _: UIImage, pngFileURL: URL, permalink: URL) -> [Any] {
        [pngFileURL, permalink]
    }
}
