//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
@testable import Spud

/// Exercises ``ShareCardImageRenderer``: the fixed-scale (3x) native / square /
/// story compositions, the PNG alt-text metadata written via `CGImageDestination`
/// and read back with `CGImageSourceCopyPropertiesAtIndex`, and the temp-file
/// name sanitization. Uses plain fixed-size views and one real ``ShareCardView``
/// so nothing here needs the network or a booted-device UI.
@MainActor
struct ShareCardImageRendererTests {
    // MARK: - render: canvas sizes

    @Test
    func render_native_isCardWidthTimesScaleThree() {
        let image = ShareCardImageRenderer.render(
            cardView: dummyCard(height: 500),
            options: options(canvas: .native)
        )
        // native hugs the card: 372pt x scale 3 = 1116px wide, height follows the card.
        #expect(pixelWidth(image) == 1116)
        #expect(pixelHeight(image) == 1500)
    }

    @Test
    func render_square_is1080x1080() {
        let image = ShareCardImageRenderer.render(
            cardView: dummyCard(height: 500),
            options: options(canvas: .square)
        )
        #expect(pixelWidth(image) == 1080)
        #expect(pixelHeight(image) == 1080)
    }

    @Test
    func render_story_is1080x1920() {
        let image = ShareCardImageRenderer.render(
            cardView: dummyCard(height: 500),
            options: options(canvas: .story)
        )
        #expect(pixelWidth(image) == 1080)
        #expect(pixelHeight(image) == 1920)
    }

    @Test
    func render_realShareCard_native_hugsCardAtFullWidth() throws {
        // A real card exercises the renderer's layout pass end to end (the card
        // has no width constraint of its own; the renderer pins it to 372pt).
        let card = try ShareCardView(
            content: sampleContent(),
            options: options(canvas: .native),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: #require(TimeZone(identifier: "GMT"))
        )
        let image = ShareCardImageRenderer.render(cardView: card, options: options(canvas: .native))
        #expect(pixelWidth(image) == 1116)
        #expect(pixelHeight(image) > 0)
    }

    // MARK: - writePNG: metadata

    @Test
    func writePNG_embedsAltTextInPngDescription() async throws {
        let altText = "Lemmy post in c/linux@lemmy.ml: \"Hello\", 12 points."
        let url = try await ShareCardImageRenderer.writePNG(swatch(), altText: altText, suggestedName: "post")
        let properties = try readProperties(of: url)
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        #expect(png?[kCGImagePropertyPNGDescription] as? String == altText)
    }

    @Test
    func writePNG_embedsAltTextInIptcCaption() async throws {
        let altText = "Comment by u/bob@lemmy.ml: \"Nice\", 3 points."
        let url = try await ShareCardImageRenderer.writePNG(swatch(), altText: altText, suggestedName: "comment")
        let properties = try readProperties(of: url)
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        #expect(iptc?[kCGImagePropertyIPTCCaptionAbstract] as? String == altText)
    }

    @Test
    func writePNG_producesPngExtension() async throws {
        let url = try await ShareCardImageRenderer.writePNG(swatch(), altText: "alt", suggestedName: "anything")
        #expect(url.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func writePNG_sanitizesSuggestedNameIntoTheFilename() async throws {
        let url = try await ShareCardImageRenderer.writePNG(
            swatch(),
            altText: "alt",
            suggestedName: "danger/ous:name"
        )
        let stem = url.deletingPathExtension().lastPathComponent
        #expect(!stem.contains("/"))
        #expect(!stem.contains(":"))
    }

    // MARK: - writePNG: stale-export sweep

    /// Calling `writePNG` sweeps sibling export subdirectories older than
    /// ``ShareCardImageRenderer/staleExportAge`` while leaving fresh ones (and
    /// the one it just wrote) intact.
    @Test
    func writePNG_sweepsStaleSiblingExportDirectories() async throws {
        let fileManager = FileManager.default
        let root = ShareCardImageRenderer.shareRootDirectory

        // A stale export dir, backdated well past the 24h threshold.
        let stale = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stale, withIntermediateDirectories: true)
        let staleDate = Date(timeIntervalSinceNow: -48 * 60 * 60)
        try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: stale.path)

        // A fresh export dir (just created).
        let fresh = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: fresh, withIntermediateDirectories: true)

        let written = try await ShareCardImageRenderer.writePNG(swatch(), altText: "alt", suggestedName: "sweep")

        #expect(!fileManager.fileExists(atPath: stale.path)) // swept
        #expect(fileManager.fileExists(atPath: fresh.path)) // survives
        #expect(fileManager.fileExists(atPath: written.path)) // the new export survives

        // Clean up what this test created.
        try? fileManager.removeItem(at: fresh)
        try? fileManager.removeItem(at: written.deletingLastPathComponent())
    }

    /// The sweep is age-gated in both directions: a directory younger than the
    /// threshold survives, and the same directory backdated past the threshold is
    /// removed. Uses the real clock (never a future `now`) so it can't delete a
    /// concurrent test's fresh export dir under Swift Testing's parallelism —
    /// only its own backdated directory is ever eligible.
    @Test
    func sweepStaleExports_isAgeGatedBothWays() throws {
        let fileManager = FileManager.default
        let dir = ShareCardImageRenderer.shareRootDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        // Fresh (1h old): a real-clock sweep leaves it.
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60 * 60)], ofItemAtPath: dir.path)
        ShareCardImageRenderer.sweepStaleExports()
        #expect(fileManager.fileExists(atPath: dir.path))

        // Backdated past the threshold: the same sweep now removes it.
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -48 * 60 * 60)],
            ofItemAtPath: dir.path
        )
        ShareCardImageRenderer.sweepStaleExports()
        #expect(!fileManager.fileExists(atPath: dir.path))
    }

    // MARK: - sanitizedFileName

    @Test
    func sanitizedFileName_replacesPathSeparators() {
        #expect(ShareCardImageRenderer.sanitizedFileName("linux post/update:v2") == "linux post update v2")
    }

    @Test
    func sanitizedFileName_stripsControlCharacters() {
        #expect(ShareCardImageRenderer.sanitizedFileName("a\nb\tc") == "a b c")
    }

    @Test
    func sanitizedFileName_fallsBackWhenEmpty() {
        #expect(ShareCardImageRenderer.sanitizedFileName("") == "spud-share")
        #expect(ShareCardImageRenderer.sanitizedFileName("   ") == "spud-share")
        #expect(ShareCardImageRenderer.sanitizedFileName("///") == "spud-share")
    }

    @Test
    func sanitizedFileName_capsLength() {
        let long = String(repeating: "x", count: 400)
        #expect(ShareCardImageRenderer.sanitizedFileName(long).count <= 80)
    }

    // MARK: - shareItems

    @Test
    func shareItems_areFileURLThenPermalink() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/share.png")
        let permalink = try #require(URL(string: "https://lemmy.ml/post/1"))
        let items = ShareCardImageRenderer.shareItems(image: swatch(), pngFileURL: fileURL, permalink: permalink)
        #expect(items.count == 2)
        #expect(items.first as? URL == fileURL)
        #expect(items.last as? URL == permalink)
    }

    // MARK: - Fixtures

    /// A plain fixed-size stand-in for a card. Explicit width + height
    /// constraints make `systemLayoutSizeFitting` deterministic without a real
    /// card's content.
    private func dummyCard(width: CGFloat = ShareCardMetrics.width, height: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func options(canvas: ShareCardOptions.Canvas) -> ShareCardOptions {
        ShareCardOptions(canvas: canvas)
    }

    private func sampleContent() -> ShareCardContent {
        let summary = ShareCardContent.PostSummary(
            title: "Understanding Auto Layout from first principles",
            bodyPlain: "A short lead paragraph.",
            communityName: "Linux",
            communityHandle: "c/linux@lemmy.ml",
            communityIconUrl: nil,
            creatorHandle: "u/torvalds@lemmy.ml",
            score: 3402,
            commentCount: 612,
            published: Date(timeIntervalSince1970: 1_752_336_180),
            permalink: URL(string: "https://lemmy.ml/post/1284920")!,
            mediaUrl: nil,
            mediaAspectIsWide: false,
            isNsfw: false
        )
        return ShareCardContent(post: summary, chain: [], kind: .post)
    }

    /// A tiny solid image to feed `writePNG` — metadata, not pixels, is under test.
    private func swatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func pixelWidth(_ image: UIImage) -> Int {
        Int((image.size.width * image.scale).rounded())
    }

    private func pixelHeight(_ image: UIImage) -> Int {
        Int((image.size.height * image.scale).rounded())
    }

    private func readProperties(of url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }
}
