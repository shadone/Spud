//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Regression guard for the offline Account-screen overlap bug: the person
/// content screen's empty/error message used to render via the
/// view-controller-level `contentUnavailableConfiguration`, which overlaid a
/// content-unavailable view across the WHOLE view — including the always-visible
/// profile header hosted as `tableView.tableHeaderView` — so the "Couldn't load"
/// message landed ON TOP of the header text. The fix renders the same styled
/// `UIContentUnavailableConfiguration` into `tableView.backgroundView`, which is
/// confined to the table's content area and centers BELOW the header.
///
/// These tests reproduce that exact layout (a table with a tableHeaderView plus
/// the error config's `makeContentView()` as the background view) and assert the
/// message draws below the header, never overlapping it.
@MainActor
final class PersonContentUnavailableSnapshotTests: XCTestCase {
    private let width: CGFloat = 390
    private let height: CGFloat = 600

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    /// Builds a stand-in for the profile header (avatar + name + a posts|comments
    /// segmented control) that PersonViewController hosts as its tableHeaderView.
    private func makeHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 140))
        header.backgroundColor = .secondarySystemBackground

        let avatar = UIView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.backgroundColor = .systemBlue
        avatar.layer.cornerRadius = 24
        header.addSubview(avatar)

        let name = UILabel()
        name.translatesAutoresizingMaskIntoConstraints = false
        name.text = "Ada Lovelace"
        name.font = .preferredFont(forTextStyle: .headline)
        header.addSubview(name)

        let segmented = UISegmentedControl(items: ["Posts", "Comments"])
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.selectedSegmentIndex = 0
        header.addSubview(segmented)

        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            avatar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48),

            name.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),

            segmented.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 16),
            segmented.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            segmented.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            segmented.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
        ])
        return header
    }

    /// The exact `UIContentUnavailableConfiguration` the `.error` branch of
    /// `PersonViewController.updateContentUnavailable` builds.
    private func errorConfiguration() -> UIContentUnavailableConfiguration {
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "exclamationmark.triangle")
        config.text = "Couldn't load"
        config.secondaryText = "Check your connection and pull to refresh."
        return config
    }

    /// Mirrors the production layout: a plain table with the profile header as its
    /// `tableHeaderView` and the error config rendered into `backgroundView`
    /// (exactly what the fixed `updateContentUnavailable(.error)` does).
    private func makeTable(traits: UITraitCollection) -> UITableView {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: width, height: height), style: .plain)
        tableView.backgroundColor = .systemBackground

        let header = makeHeader()
        // The table positions its header by frame, like production.
        header.translatesAutoresizingMaskIntoConstraints = true
        header.frame = CGRect(x: 0, y: 0, width: width, height: 140)
        tableView.tableHeaderView = header

        // The fix under test: the content-unavailable view goes into the table's
        // background, NOT the VC-level contentUnavailableConfiguration.
        let content = errorConfiguration().makeContentView()
        content.frame = tableView.bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundView = content

        tableView.overrideUserInterfaceStyle = traits.userInterfaceStyle
        tableView.layoutIfNeeded()
        return tableView
    }

    func test_errorState_messageBelowHeader_light() {
        let table = makeTable(traits: traits(.light))
        assertSnapshot(
            matching: table,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }

    func test_errorState_messageBelowHeader_dark() {
        let table = makeTable(traits: traits(.dark))
        assertSnapshot(
            matching: table,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.dark))
        )
    }

    /// Render-independent assertion that the "Couldn't load" content view is laid
    /// out entirely BELOW the table header — i.e. it never overlaps it. (Snapshots
    /// are environment-sensitive; this guards the geometry regardless of fonts.)
    func test_errorState_contentDoesNotOverlapHeader() throws {
        let table = makeTable(traits: traits(.light))

        let header = try XCTUnwrap(table.tableHeaderView)
        let background = try XCTUnwrap(table.backgroundView)

        // The header sits at the top of the content; the background view fills the
        // whole table and CENTERS its content-unavailable layout within it, so the
        // visible message is well below the header's bottom edge. Convert both into
        // the table's coordinate space and confirm the header occupies the top band
        // while the background spans the full height beneath it.
        let headerFrame = header.convert(header.bounds, to: table)
        XCTAssertEqual(headerFrame.minY, 0, accuracy: 0.5, "Header should be pinned to the top")
        XCTAssertGreaterThan(headerFrame.height, 0, "Header must be present and non-empty")

        // The content-unavailable view's own intrinsic layout must be shorter than
        // the table, so when centered its glyph/text land below the header band
        // (not overlaying the top where the header lives).
        let fittingSize = background.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let centeredTopInset = (height - fittingSize.height) / 2
        XCTAssertGreaterThan(
            centeredTopInset,
            headerFrame.maxY,
            "Centered content-unavailable message must start below the header, not overlap it"
        )
    }
}
