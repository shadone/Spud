//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import SpudMarkdownKit

final class MarkdownMediaSnapshotTests: XCTestCase {
    @MainActor
    private func render(kind: MarkdownContextKind, width: CGFloat = 360) -> UIView {
        let context = MarkdownContext(kind: kind)
        let audioURL = URL(string: "https://example.com/clip.mp3")!
        let videoURL = URL(string: "https://example.com/demo.mp4")!
        let imageURL = URL(string: "https://example.com/photo.jpg")!

        let audio = AudioBlockView(url: audioURL, context: context, onTap: nil)
        let video = VideoBlockView(url: videoURL, context: context, onTap: nil)

        // loader: nil — state is injected synchronously below via apply(state:) for deterministic snapshots
        let loaded = ImageBlockView(
            image: MarkdownImage(url: imageURL, altText: "A teal placeholder with a caption."),
            context: context, onTapImage: nil, onOpenInBrowser: nil, onContentSizeChange: nil, loader: nil
        )
        loaded.apply(state: .loaded(Self.stubImage(width: 320, height: 180)))

        let failed = ImageBlockView(
            image: MarkdownImage(url: imageURL, altText: "Alt text still shows when an image fails."),
            context: context, onTapImage: nil, onOpenInBrowser: nil, onContentSizeChange: nil, loader: nil
        )
        failed.apply(state: .failed)

        let stack = UIStackView(arrangedSubviews: [audio, video, loaded, failed])
        stack.axis = .vertical
        stack.spacing = context.interBlockGap
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = .systemBackground
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.widthAnchor.constraint(equalToConstant: width - 32),
        ])
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.layoutIfNeeded()
        container.frame = CGRect(
            x: 0, y: 0, width: width,
            height: container.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
            ).height
        )
        return container
    }

    private static func stubImage(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    @MainActor
    func test_mediaPostLight() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }

    @MainActor
    func test_mediaPostDark() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: MarkdownSnapshotDeterminism.traits(.dark)))
    }

    @MainActor
    func test_mediaCommentLight() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }

    @MainActor
    func test_mediaCommentDark() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: MarkdownSnapshotDeterminism.traits(.dark)))
    }
}
