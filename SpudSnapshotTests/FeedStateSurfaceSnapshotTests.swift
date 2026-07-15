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

/// Regression guard for the community-feed overlap bug (fixed in commit
/// 1631d27f): the feed's full error/empty state used to render via the
/// view-controller-level `contentUnavailableConfiguration`, a transparent
/// overlay drawn across the WHOLE view — including a scrolling header hosted
/// as the table's `tableHeaderView` (the community header) — so "Couldn't
/// reach <host>" rendered see-through ON TOP of the header. The fix renders
/// the same styled `UIContentUnavailableConfiguration` into a
/// `FeedStateSurfaceView` hosted as the table's `backgroundView`, below the
/// header in z-order and top-inset by the header's height so the surface
/// centers in the below-header region instead of the full bounds.
///
/// Mirrors `PersonContentUnavailableSnapshotTests` (the b7ecc4ce precedent this
/// fix follows: same "render into `backgroundView`" idea) but deliberately
/// uses a header TALLER THAN HALF the table height. Person's fix only moved
/// the surface below the header in z-order — its content still CENTERS in the
/// full bounds, so a sufficiently tall header would still cover it. This
/// surface additionally top-insets by the header's height
/// (`FeedStateSurfaceView.topInset`, mirroring the loading skeleton's own
/// `topInset`), so it centers in the space BELOW the header instead — these
/// snapshots and the geometry test below pin that improvement.
@MainActor
final class FeedStateSurfaceSnapshotTests: XCTestCase {
    private let width: CGFloat = 390
    private let height: CGFloat = 600

    /// Taller than half the 600pt table height (mirrors
    /// `PostListStateSurfaceTests.headerHeight`) — under a bounds-centered
    /// layout (Person's residual) the surface's centered content would land
    /// inside the header's own band and be invisible; the inset fix keeps it
    /// below the header instead, which these snapshots and the geometry test
    /// pin.
    private let headerHeight: CGFloat = 420

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    /// A stand-in for the community screen's scrolling header (banner + icon +
    /// name + description + subscribe button) — the same shape
    /// `CommunityViewController` hosts as `tableHeaderView` via
    /// `setScrollingHeaderView`.
    private func makeHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: headerHeight))
        header.backgroundColor = .secondarySystemBackground
        header.clipsToBounds = true

        let banner = UIView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.backgroundColor = .systemTeal
        header.addSubview(banner)

        let icon = UIView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.backgroundColor = .systemBlue
        icon.layer.cornerRadius = 28
        icon.layer.borderWidth = 3
        icon.layer.borderColor = UIColor.secondarySystemBackground.cgColor
        header.addSubview(icon)

        let name = UILabel()
        name.translatesAutoresizingMaskIntoConstraints = false
        name.text = "technology@lemmy.world"
        name.font = .preferredFont(forTextStyle: .headline)
        header.addSubview(name)

        let description = UILabel()
        description.translatesAutoresizingMaskIntoConstraints = false
        description.text = "A place to share and discuss the latest developments in technology."
        description.font = .preferredFont(forTextStyle: .subheadline)
        description.textColor = .secondaryLabel
        description.numberOfLines = 0
        header.addSubview(description)

        let subscribe = UIButton(configuration: .borderedProminent())
        subscribe.translatesAutoresizingMaskIntoConstraints = false
        subscribe.configuration?.title = "Subscribe"
        header.addSubview(subscribe)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: header.topAnchor),
            banner.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: 160),

            icon.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: -28),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),

            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            name.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            name.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            description.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 8),
            description.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            description.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            subscribe.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 16),
            subscribe.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
        ])
        return header
    }

    /// The real config shape, rebuilt via `FeedStatePresenter.descriptor` — the
    /// same source `PostListViewController.makeErrorConfiguration(for:)` reads
    /// — so the snapshot captures the actual icon + copy + buttons (minus the
    /// non-rendered action closures). Mirrors
    /// `LoadingStatesSnapshotTests.assertErrorState`.
    private func errorConfiguration(host: String?) -> UIContentUnavailableConfiguration {
        let descriptor = FeedStatePresenter.descriptor(for: .unreachable, host: host)
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: descriptor.symbolName)
        config.text = descriptor.title
        config.secondaryText = descriptor.message

        if let primary = descriptor.primary {
            var primaryConfig = UIButton.Configuration.borderedProminent()
            primaryConfig.title = primary.title
            config.button = primaryConfig
        }

        if let secondary = descriptor.secondary {
            var secondaryConfig = UIButton.Configuration.plain()
            secondaryConfig.title = secondary.title
            config.secondaryButton = secondaryConfig
        }
        return config
    }

    /// Mirrors production: a table with the community header as its
    /// `tableHeaderView` and the real `FeedStateSurfaceView` (the fix under
    /// test) as `backgroundView`, top-inset by the header's height exactly
    /// like `PostListViewController.syncStateSurfaceHeaderInset()`.
    private func makeTable(traits: UITraitCollection) -> UITableView {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: width, height: height), style: .plain)
        tableView.backgroundColor = .systemBackground

        let header = makeHeader()
        // The table positions its header by frame, like production.
        header.translatesAutoresizingMaskIntoConstraints = true
        tableView.tableHeaderView = header

        // The fix under test: the content-unavailable view goes into a
        // `FeedStateSurfaceView` hosted as the table's `backgroundView`, not
        // the VC-level `contentUnavailableConfiguration`, and is inset below
        // the header's height rather than centered in the full bounds.
        let surface = FeedStateSurfaceView()
        surface.frame = tableView.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.topInset = headerHeight
        surface.setContentView(errorConfiguration(host: "lemmy.world").makeContentView())
        tableView.backgroundView = surface

        tableView.overrideUserInterfaceStyle = traits.userInterfaceStyle
        tableView.layoutIfNeeded()
        return tableView
    }

    func test_errorState_belowTallHeader_light() {
        let table = makeTable(traits: traits(.light))
        assertSnapshot(
            matching: table,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }

    func test_errorState_belowTallHeader_dark() {
        let table = makeTable(traits: traits(.dark))
        assertSnapshot(
            matching: table,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.dark))
        )
    }

    /// Render-independent geometry lock: with a header taller than half the
    /// table, the hosted `UIContentUnavailableView` must sit ENTIRELY below
    /// the header's `maxY` — a bounds-centered layout (Person's residual)
    /// would put its centered content inside the header's own band, hidden
    /// behind it. (Snapshots are environment-sensitive; this guards the
    /// geometry regardless of fonts.)
    func test_errorState_contentEntirelyBelowHeader() throws {
        let table = makeTable(traits: traits(.light))

        let header = try XCTUnwrap(table.tableHeaderView)
        let surface = try XCTUnwrap(table.backgroundView as? FeedStateSurfaceView)
        let content = try XCTUnwrap(surface.subviews.first { $0 is UIContentUnavailableView })

        let headerFrame = header.convert(header.bounds, to: table)
        XCTAssertEqual(headerFrame.minY, 0, accuracy: 0.5, "Header should be pinned to the top")
        XCTAssertEqual(headerFrame.height, headerHeight, accuracy: 0.5, "Header must be the configured tall height")

        let contentFrame = content.convert(content.bounds, to: table)
        XCTAssertGreaterThanOrEqual(
            contentFrame.minY,
            headerFrame.maxY - 0.5,
            "The error surface must start below the header, not overlap it"
        )
        XCTAssertLessThanOrEqual(
            contentFrame.maxY,
            height + 0.5,
            "The error surface must stay within the table's visible bounds"
        )
    }
}
