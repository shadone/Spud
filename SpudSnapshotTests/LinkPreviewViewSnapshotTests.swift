//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

@MainActor
final class LinkPreviewViewSnapshotTests: XCTestCase {
    private let width: CGFloat = 350

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    private func fit(_ view: LinkPreviewView) -> CGSize {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        let h = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: h)
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        return size
    }

    func test_anchorOnly_light() throws {
        let v = LinkPreviewView()
        v.url = try XCTUnwrap(URL(string: "https://example.com/article"))
        v.anchorText = "Foobar"
        let size = fit(v)
        assertSnapshot(matching: v, as: .image(size: size, traits: traits(.light)))
    }

    func test_videoWithTitleAndThumb_dark() throws {
        let v = LinkPreviewView()
        v.url = try XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ"))
        v.anchorText = "the song"
        v.title = "Rick Astley - Never Gonna Give You Up"
        v.isVideo = true
        v.thumbnailImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            UIColor.systemGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let size = fit(v)
        assertSnapshot(matching: v, as: .image(size: size, traits: traits(.dark)))
    }
}
