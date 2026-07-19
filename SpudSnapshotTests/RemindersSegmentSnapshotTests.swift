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

/// Snapshots of the Inbox "Reminders" segment: the empty-state placeholder,
/// and `InboxReminderCell` in its six live states - `time`-kind `scheduled`
/// (a relative countdown to `fireAt`) / `fired` ("Tap to revisit"),
/// `activity`-kind (Phase 2) `scheduled` ("Watching for new comments") /
/// `fired` ("New comments · tap to catch up"), and `communityPosts`-kind (the
/// community "new posts" follow) `scheduled` ("Watching for new posts") /
/// `fired` ("New posts · tap to catch up") - each in light and dark.
///
/// Mirrors `InboxCellsSnapshotTests` (cell rendering, `StaticImageService` for
/// deterministic thumbnail loading, no network) and `InboxGatedSnapshotTests`
/// (the bare `UIContentUnavailableConfiguration` render for a state that
/// doesn't depend on the account/DB/dependency graph).
@MainActor
final class RemindersSegmentSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - Empty state

    /// The exact `UIContentUnavailableConfiguration` the `.reminders` branch
    /// of `InboxViewController.updateContentUnavailable(.empty)` builds.
    private func emptyConfiguration() -> UIContentUnavailableConfiguration {
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "bell")
        config.text = NSLocalizedString("No reminders", comment: "Inbox empty reminders title")
        config.secondaryText = NSLocalizedString(
            "Set a reminder from a post's \u{201C}Remind Me\u{2026}\u{201D} menu and it shows up here.",
            comment: "Inbox empty reminders message"
        )
        return config
    }

    func test_empty() {
        let height: CGFloat = 200
        for style in [UIUserInterfaceStyle.light, .dark] {
            let content = emptyConfiguration().makeContentView()
            content.frame = CGRect(x: 0, y: 0, width: width, height: height)
            content.backgroundColor = .systemBackground
            content.overrideUserInterfaceStyle = style
            content.layoutIfNeeded()
            assertSnapshot(
                matching: content,
                as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - InboxReminderCell

    func test_scheduled() async {
        let cell = await makeReminderCell(reminder(
            status: .scheduled,
            unseen: false,
            // A fixed relative offset (not an absolute calendar date) keeps
            // the rendered "in N days" text stable regardless of what time of
            // day the suite runs at - the delta from "now" is always exactly
            // 5 days.
            fireAt: Date(timeIntervalSinceNow: 5 * 24 * 3600)
        ))
        assertCell(cell)
    }

    func test_fired() async {
        let cell = await makeReminderCell(reminder(status: .fired, unseen: true, fireAt: nil))
        assertCell(cell)
    }

    func test_activityScheduled() async {
        let cell = await makeReminderCell(reminder(
            kind: .activity,
            status: .scheduled,
            unseen: false,
            fireAt: nil
        ))
        assertCell(cell)
    }

    func test_activityFired() async {
        let cell = await makeReminderCell(reminder(
            kind: .activity,
            status: .fired,
            unseen: true,
            fireAt: nil
        ))
        assertCell(cell)
    }

    func test_communityScheduled() async {
        let cell = await makeReminderCell(reminder(
            kind: .communityPosts,
            status: .scheduled,
            unseen: false,
            fireAt: nil
        ))
        assertCell(cell)
    }

    func test_communityFired() async {
        let cell = await makeReminderCell(reminder(
            kind: .communityPosts,
            status: .fired,
            unseen: true,
            fireAt: nil
        ))
        assertCell(cell)
    }

    // MARK: - Cell construction

    private func makeReminderCell(_ reminder: ReminderListRow) async -> InboxReminderCell {
        let cell = InboxReminderCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(with: reminder, imageService: StaticImageService())
        await settle()
        return cell
    }

    /// Pin the accent on the snapshot root and give the cell an opaque backdrop:
    /// the `.image` strategy reparents `contentView` into a fresh window, so
    /// without its own `tintColor` it would inherit system blue, and
    /// `label`-colored text would vanish on a transparent dark-mode background.
    private func prepare(_ cell: UITableViewCell) {
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
    }

    // MARK: - Rendering

    private func assertCell(
        _ cell: UITableViewCell,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func snapshot(
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

        // Host the whole cell (not just contentView) on an opaque backdrop so the
        // disclosure-chevron accessory is captured and dark-mode text stays legible.
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

    /// Let the reminder cell's thumbnail-load Task drain its (synchronous,
    /// already-ready) stream and apply the image before we measure and snapshot.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
        await Task.yield()
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    // MARK: - Fixtures

    private func reminder(
        kind: ReminderRecord.Kind = .time,
        status: ReminderRecord.Status,
        unseen: Bool,
        fireAt: Date?
    ) -> ReminderListRow {
        ReminderListRow(
            id: 1,
            postServerId: 42,
            apId: "https://lemmy.world/post/42",
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: kind.rawValue,
            status: status.rawValue,
            unseen: unseen,
            fireAt: fireAt,
            titleSnapshot: "A scenic mountain lake at golden hour",
            communityName: "photography",
            instanceHost: "lemmy.world",
            thumbnailUrl: "https://lemmy.world/pictrs/image/thumb.jpg"
        )
    }
}
