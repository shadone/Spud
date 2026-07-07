//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Renders the Apollo-signature feed media affordances to images so their
/// layout can be reviewed and regressions caught: the thumbnail states (image,
/// "GIF" badge, video play indicator, text placeholder, broken image).
///
/// Everything renders at a fixed size and pinned display scale, so these
/// references are device-independent (unlike the screen-sized markdown
/// snapshots, which are locked to iPhone 14 Pro).
///
/// (The context-menu peek `PostPreviewViewController` was reviewed the same way
/// during development and renders correctly, but its self-sizing depends on a
/// multi-pass label layout that the system drives in production and that a
/// synthetic harness reproduces only flakily — so it is verified by eye rather
/// than pinned here.)
@MainActor
final class MediaUISnapshotTests: XCTestCase {
    /// Light mode at 2x, pinned so the references don't depend on the running
    /// simulator's appearance or screen scale.
    private let traits = UITraitCollection(traitsFrom: [
        UITraitCollection(userInterfaceStyle: .light),
        UITraitCollection(displayScale: 2),
        SnapshotDeterminism.contentSizeTrait,
    ])

    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func thumbnail(_ configure: (PostListThumbnailImageView) -> Void) -> PostListThumbnailImageView {
        let view = PostListThumbnailImageView()
        configure(view)
        return view
    }

    private func assertThumbnail(
        _ view: PostListThumbnailImageView,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: 64, height: 64), traits: traits),
            file: file,
            testName: testName,
            line: line
        )
    }

    func test_thumbnail_image() {
        assertThumbnail(thumbnail { $0.thumbnailType = .image(solidImage(.systemTeal)) })
    }

    func test_thumbnail_gifBadge() {
        assertThumbnail(thumbnail {
            $0.thumbnailType = .image(solidImage(.systemTeal))
            $0.badgeText = "GIF"
        })
    }

    func test_thumbnail_videoPlayIcon() {
        assertThumbnail(thumbnail {
            $0.thumbnailType = .image(solidImage(.systemIndigo))
            $0.showsPlayIcon = true
        })
    }

    func test_thumbnail_linkBadge() {
        assertThumbnail(thumbnail {
            $0.thumbnailType = .image(solidImage(.systemTeal))
            $0.badgeSymbolName = "globe"
        })
    }

    func test_thumbnail_link() {
        assertThumbnail(thumbnail { $0.thumbnailType = .link })
    }

    func test_thumbnail_text() {
        assertThumbnail(thumbnail { $0.thumbnailType = .text })
    }

    func test_thumbnail_broken() {
        assertThumbnail(thumbnail { $0.thumbnailType = .imageFailure })
    }
}
