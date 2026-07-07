//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Renders the media-adjacent UI components to images so their layout can be
/// reviewed and regressions caught: the external-link preview (`LinkPreviewView`)
/// with and without a thumbnail and with a long, truncating host+path; the media
/// type badge (`MediaBadgeView`) for "GIF" and "MP4"; the bordered "ALT" marker
/// (`AltBadgeLabel`) at two point sizes; and the alt-text bottom sheet
/// (`AltTextSheetViewController`) with short, long, and empty descriptions.
///
/// The three views render at fixed sizes with a pinned display scale, and the
/// sheet renders at a pinned `ViewImageConfig` (iPhone 13 Pro), so every
/// reference is device-independent — it records and verifies identically on any
/// simulator. Thumbnails are solid-color images so no async loading occurs.
@MainActor
final class MediaComponentsSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func assertComponent(
        _ view: UIView,
        size: CGSize,
        style: UIUserInterfaceStyle,
        named: String,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            matching: view,
            as: .image(size: size, traits: traits(style)),
            named: named,
            testName: testName,
            line: line
        )
    }

    // MARK: - LinkPreviewView

    private func linkPreview(url: String, thumbnail: UIImage?) -> LinkPreviewView {
        let view = LinkPreviewView()
        view.tintColor = lemmyTeal
        view.url = URL(string: url)!
        view.thumbnailImage = thumbnail
        return view
    }

    func test_linkPreview_withThumbnail() {
        let size = CGSize(width: 358, height: 64)
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertComponent(
                linkPreview(
                    url: "https://example.com/articles/the-quiet-web",
                    thumbnail: solidImage(.systemTeal)
                ),
                size: size,
                style: style,
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    func test_linkPreview_withoutThumbnail() {
        let size = CGSize(width: 358, height: 64)
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertComponent(
                linkPreview(
                    url: "https://example.com/articles/the-quiet-web",
                    thumbnail: nil
                ),
                size: size,
                style: style,
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    func test_linkPreview_longHostAndPath() {
        let size = CGSize(width: 358, height: 64)
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertComponent(
                linkPreview(
                    url: "https://very-long-subdomain.example-newspaper.co.uk/2026/06/14/a-rather-long-article-slug-that-will-not-fit",
                    thumbnail: solidImage(.systemIndigo)
                ),
                size: size,
                style: style,
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - MediaBadgeView

    private func mediaBadge(_ text: String) -> MediaBadgeView {
        let view = MediaBadgeView()
        view.text = text
        return view
    }

    func test_mediaBadge_gif() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let badge = mediaBadge("GIF")
            assertComponent(
                badge,
                size: badge.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize),
                style: style,
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    func test_mediaBadge_mp4() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let badge = mediaBadge("MP4")
            assertComponent(
                badge,
                size: badge.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize),
                style: style,
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - AltBadgeLabel

    /// The badge draws white text on a translucent white border; give the
    /// snapshot the dark media-viewer backdrop it sits on so it stays legible
    /// (white-on-transparent would vanish against the snapshot's clear root).
    private func altBadge(pointSize: CGFloat) -> UIView {
        let badge = AltBadgeLabel(pointSize: pointSize)
        let container = UIView()
        container.backgroundColor = UIColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            badge.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }

    func test_altBadge_pointSize10() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = altBadge(pointSize: 10)
            assertComponent(
                view,
                size: view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize),
                style: style,
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    func test_altBadge_pointSize12() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = altBadge(pointSize: 12)
            assertComponent(
                view,
                size: view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize),
                style: style,
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - AltTextSheetViewController

    private func assertSheet(
        altText: String,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewController = AltTextSheetViewController(altText: altText)
            assertSnapshot(
                matching: viewController,
                as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    func test_altSheet_short() {
        assertSheet(altText: "A red bicycle leaning against a brick wall.")
    }

    func test_altSheet_long() {
        assertSheet(
            altText: "A wide landscape photograph taken at golden hour: a calm alpine lake mirrors the surrounding snow-capped peaks, with a lone wooden rowboat moored at a small jetty in the foreground. Wisps of mist hang over the far shore, and the warm light catches the tops of the pines along the right-hand ridge."
        )
    }

    func test_altSheet_empty() {
        assertSheet(altText: "")
    }
}
