//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUtilKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the instance-picker cell plus the instance icon view across
/// their visual states, each in light and dark.
///
/// - `SiteListSiteCell`: a loaded instance (with a resolved icon via
///   `StaticImageService`) and an instance with no icon (placeholder).
/// - `SiteListIconImageView`: its three rendered `IconType` states — a loaded
///   image, the empty `noIcon` placeholder, and the `failure` broken-icon plate.
///
/// (The account-switcher rows now render in SwiftUI; their visual states are
/// covered by `AccountSwitcherSnapshotTests`.)
///
/// Cells render from a `SiteListRow` fixture and a deterministic image service,
/// with no database or network. Each cell is rendered at a fixed width and pinned
/// display scale, and the icon view at a fixed size, so the references are
/// device-independent.
@MainActor
final class InstancesAccountsCellsSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - SiteListSiteCell

    func test_site_loaded() async {
        await assertSiteCell(
            row: siteRow(
                hostname: "lemmy.world",
                descriptionText: "The largest general-purpose Lemmy server. Big, fast and well-moderated.",
                iconUrl: URL(string: "https://lemmy.world/pictrs/image/icon.png"),
                uptimeAllTime: 99.7,
                usersActiveMonth: 58000
            ),
            imageService: StaticImageService()
        )
    }

    func test_site_missingIcon() async {
        await assertSiteCell(
            row: siteRow(
                hostname: "spud.cafe",
                descriptionText: "A cozy little corner run by one admin.",
                iconUrl: nil
            ),
            imageService: StaticImageService()
        )
    }

    /// Stats line with only some metrics known: total users is nil, so the line
    /// renders just "… active · …% uptime" (nil components are omitted, never "0").
    func test_site_partialStats() async {
        await assertSiteCell(
            row: siteRow(
                hostname: "partial.example",
                descriptionText: "Known active users and uptime, but no total-user count.",
                iconUrl: nil,
                usersTotal: nil,
                uptimeAllTime: 100,
                usersActiveMonth: 1900
            ),
            imageService: StaticImageService()
        )
    }

    // MARK: - SiteListIconImageView

    func test_icon_image() {
        assertIconView(.image(solidImage(.systemIndigo)))
    }

    func test_icon_noIcon() {
        assertIconView(.noIcon)
    }

    func test_icon_failure() {
        assertIconView(.failure)
    }

    // MARK: - SiteListSiteCell rendering

    private func assertSiteCell(
        row: SiteListRow,
        imageService: @autoclosure () -> ImageServiceType,
        testName: String = #function,
        line: UInt = #line
    ) async {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = SiteListSiteCell(style: .default, reuseIdentifier: nil)
            pinAccent(cell)
            let viewModel = SiteListSiteViewModel(
                row: row,
                dependencies: SnapshotDependencies(imageService: imageService())
            )
            cell.configure(with: viewModel)
            await settle()
            snapshotCell(cell, style: style, testName: testName, line: line)
        }
    }

    // MARK: - SiteListIconImageView rendering

    private func assertIconView(
        _ iconType: SiteListIconImageView.IconType,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = SiteListIconImageView()
            view.tintColor = lemmyTeal
            view.iconType = iconType
            assertSnapshot(
                matching: view,
                as: .image(size: CGSize(width: 40, height: 40), traits: traits(style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    // MARK: - Shared cell helpers

    private func pinAccent(_ cell: UITableViewCell) {
        // Pin the accent on the snapshot root: the `.image` strategy reparents
        // `contentView` into a fresh window, so without its own tintColor it
        // would inherit the window's system blue instead of the brand teal.
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        // The cell is transparent and sits on the table's background at runtime;
        // give the snapshot the same opaque backdrop so `label`-colored text
        // stays legible (white-on-transparent would vanish in dark mode).
        cell.contentView.backgroundColor = .systemBackground
    }

    private func snapshotCell(
        _ cell: UITableViewCell,
        style: UIUserInterfaceStyle,
        testName: String,
        line: UInt
    ) {
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        cell.layoutIfNeeded()
        let height = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        // Host the whole cell (not just contentView) on an opaque backdrop, so the
        // cell's accessory (the disclosure chevron) is captured and
        // `label`-colored text stays legible in dark mode.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        container.backgroundColor = .systemBackground
        container.tintColor = lemmyTeal
        cell.frame = container.bounds
        container.addSubview(cell)
        container.layoutIfNeeded()

        assertSnapshot(
            matching: container,
            as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    /// Let the site cell's image-load observation drain its scripted stream and
    /// apply the resulting icon before we measure and snapshot.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
        await Task.yield()
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    // MARK: - Dependencies

    /// Minimal container for `SiteListSiteViewModel.Dependencies`
    /// (`HasVoid & HasImageService`). The view model only reads `imageService`.
    @MainActor
    private struct SnapshotDependencies: HasVoid, HasImageService {
        let imageService: ImageServiceType
    }

    // MARK: - Fixtures

    private func solidImage(
        _ color: UIColor,
        size: CGSize = CGSize(width: 200, height: 200)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func siteRow(
        hostname: String,
        descriptionText: String?,
        iconUrl: URL?,
        usersTotal: Int64? = 1_200_000,
        uptimeAllTime: Double? = nil,
        usersActiveMonth: Int64? = nil
    ) -> SiteListRow {
        SiteListRow(
            id: 1,
            instance: InstanceActorId(from: "https://\(hostname)")!,
            hostname: hostname,
            name: hostname,
            descriptionText: descriptionText,
            iconUrl: iconUrl,
            score: 0.9,
            usersTotal: usersTotal,
            usersActiveMonth: usersActiveMonth,
            uptimeAllTime: uptimeAllTime,
            isNsfw: false,
            isOpenRegistration: true,
            languageCodes: ["en"],
            tags: ["General"]
        )
    }
}
