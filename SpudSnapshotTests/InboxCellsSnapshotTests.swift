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

/// Snapshots of the inbox table cells across their read/unread states, each in
/// light and dark.
///
/// `InboxCommentCell` (replies and mentions) is a pure text cell — it renders
/// straight from its `configure(...)` arguments with no image loading, so it is
/// snapshot read and unread. `InboxConversationCell` (the Messages list) loads
/// a correspondent avatar asynchronously; a `StaticImageService` drives that
/// deterministically (no network), and the test covers read, unread, and a long
/// preview that truncates to the cell's two-line limit.
///
/// Cells render at a fixed width and pinned display scale, so the references are
/// device-independent.
@MainActor
final class InboxCellsSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - InboxCommentCell

    func test_comment_read() {
        let cell = makeCommentCell(isRead: true)
        assertCell(cell)
    }

    func test_comment_unread() {
        let cell = makeCommentCell(isRead: false)
        assertCell(cell)
    }

    // MARK: - InboxConversationCell

    func test_conversation_read() async {
        let cell = await makeConversationCell(conversation: conversation(hasUnread: false))
        assertCell(cell)
    }

    func test_conversation_unread() async {
        let cell = await makeConversationCell(conversation: conversation(hasUnread: true))
        assertCell(cell)
    }

    func test_conversation_longPreviewTruncates() async {
        let longPreview = """
            Hey, just circling back on the thread from last week — I read through all of \
            your points and I think there is a lot to unpack here, so let me try to respond \
            to each one in turn before we lose the context entirely.
            """
        let cell = await makeConversationCell(
            conversation: conversation(hasUnread: false, latestContent: longPreview)
        )
        assertCell(cell)
    }

    func test_conversation_sending() async {
        let cell = await makeConversationCell(
            conversation: conversation(hasUnread: false, pendingStatus: .sending)
        )
        assertCell(cell)
    }

    func test_conversation_failed() async {
        let cell = await makeConversationCell(
            conversation: conversation(hasUnread: false, pendingStatus: .failed)
        )
        assertCell(cell)
    }

    // MARK: - Cell construction

    private func makeCommentCell(isRead: Bool) -> InboxCommentCell {
        let cell = InboxCommentCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(
            creatorName: "ansel",
            content: "Beautiful shot — the light on the ridge is unreal. What time of day was this?",
            postTitle: "A scenic mountain lake at golden hour",
            communityName: "photography",
            isRead: isRead
        )
        return cell
    }

    private func makeConversationCell(conversation: InboxConversation) async -> InboxConversationCell {
        let cell = InboxConversationCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(with: conversation, imageService: StaticImageService())
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

    /// Let the conversation cell's avatar-load Task drain its (synchronous,
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

    private func conversation(
        hasUnread: Bool,
        unreadCount: Int? = nil,
        latestContent: String = "Sounds good, see you then!",
        pendingStatus: InboxConversationPendingStatus? = nil
    ) -> InboxConversation {
        InboxConversation(
            correspondentId: 1,
            correspondentName: "Marie",
            correspondentAvatarUrl: URL(string: "https://lemmy.world/pictrs/image/avatar.png"),
            latestContent: latestContent,
            latestPublished: Date(timeIntervalSinceNow: -3 * 3600),
            unreadCount: hasUnread ? (unreadCount ?? 1) : 0,
            pendingStatus: pendingStatus
        )
    }
}
