//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Proves `CommunityHeaderView`'s title-row badge layout for every
/// hideable-pill combination the NSFW + meta pills can be in: meta alone, NSFW
/// + meta BOTH shown (the collision risk two independently-hidden pills
/// create), and neither. The pills sit in a horizontal `UIStackView` after the
/// title, so a hidden arranged subview collapses its width and spacing
/// entirely instead of leaving a dead gap — these snapshots are what proves
/// that holds for every combination, not just NSFW alone.
@MainActor
final class CommunityHeaderMetaSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotDeterminism.pinAccent()
    }

    private let width: CGFloat = 390

    func test_metaOnly() {
        assertHeader(isNsfw: false, isMeta: true)
    }

    func test_nsfwAndMeta_bothShown() {
        assertHeader(isNsfw: true, isMeta: true)
    }

    func test_neitherPill() {
        assertHeader(isNsfw: false, isMeta: false)
    }

    // MARK: - Configuration + rendering

    private func makeHeader(isNsfw: Bool, isMeta: Bool) -> CommunityHeaderView {
        let header = CommunityHeaderView()
        header.configure(
            title: "Technology",
            qualifiedName: "!technology@lemmy.world",
            subscribersText: "42k",
            postsText: "8.1k",
            vitalityText: nil,
            descriptionMarkdown: nil,
            subscribed: .notSubscribed,
            isNsfw: isNsfw,
            isMeta: isMeta,
            blurBanner: false
        )
        return header
    }

    /// Renders a fresh header (per style, so no autolayout constraint carries
    /// over between iterations) pinned to a fixed-width container, fitted to
    /// its content height, and snapshotted in both appearances.
    private func assertHeader(
        isNsfw: Bool,
        isMeta: Bool,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let header = makeHeader(isNsfw: isNsfw, isMeta: isMeta)
            header.translatesAutoresizingMaskIntoConstraints = false

            let container = UIView()
            container.backgroundColor = .systemBackground
            container.addSubview(header)
            NSLayoutConstraint.activate([
                header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                header.topAnchor.constraint(equalTo: container.topAnchor),
                header.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            container.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
            container.layoutIfNeeded()

            let height = container.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            container.frame = CGRect(x: 0, y: 0, width: width, height: height)
            container.layoutIfNeeded()

            assertSnapshot(
                matching: container,
                as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }
}
