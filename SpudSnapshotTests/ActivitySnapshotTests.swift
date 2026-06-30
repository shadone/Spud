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

/// Snapshots for the Activity timeline cells and the filter-chip bar.
///
/// `ActivityPostCell` and `ActivityCommentCell` are purely data-driven (no
/// image loading, no async) so they snapshot deterministically. The filter bar
/// is a `UIScrollView` that is rendered at a fixed width that fits all chips.
/// All tests run light + dark; record on iPhone 17 Pro, iOS 26.3.
@MainActor
final class ActivitySnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - ActivityPostCell

    func test_postCell_upvoted() {
        let cell = ActivityPostCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(with: upvotePostItem(), post: samplePost())
        assertCell(cell)
    }

    func test_postCell_downvoted() {
        let cell = ActivityPostCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(with: downvotePostItem(), post: samplePost())
        assertCell(cell)
    }

    func test_postCell_read() {
        let cell = ActivityPostCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(with: readPostItem(), post: samplePost())
        assertCell(cell)
    }

    // MARK: - ActivityCommentCell

    func test_commentCell_commented() {
        let cell = ActivityCommentCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(with: commentItem(), comment: sampleComment())
        assertCell(cell)
    }

    func test_commentCell_saved() {
        let cell = ActivityCommentCell(style: .default, reuseIdentifier: nil)
        prepare(cell)
        cell.configure(with: saveCommentItem(), comment: sampleComment())
        assertCell(cell)
    }

    // MARK: - ActivityFilterBarView

    func test_filterBar_noActiveFilters() {
        let bar = ActivityFilterBarView()
        bar.frame = CGRect(x: 0, y: 0, width: width, height: 50)
        bar.tintColor = lemmyTeal
        bar.layoutIfNeeded()
        assertView(bar, height: 50)
    }

    func test_filterBar_withActiveFilters() {
        let bar = ActivityFilterBarView()
        bar.activeFilters = [.post, .vote]
        bar.frame = CGRect(x: 0, y: 0, width: width, height: 50)
        bar.tintColor = lemmyTeal
        bar.layoutIfNeeded()
        assertView(bar, height: 50)
    }

    // MARK: - Cell helpers

    private func prepare(_ cell: UITableViewCell) {
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
    }

    private func assertCell(
        _ cell: UITableViewCell,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            snapshotCell(cell, style: style, testName: testName, line: line)
        }
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

    private func assertView(
        _ view: UIView,
        height: CGFloat,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
            container.backgroundColor = .systemBackground
            container.tintColor = lemmyTeal
            view.frame = container.bounds
            container.addSubview(view)
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
            UITraitCollection(displayScale: 3),
        ])
    }

    // MARK: - Test data

    private let referenceDate = Date(timeIntervalSince1970: 1_751_000_000) // 2025-06-27

    private func upvotePostItem() -> ActivityItem {
        ActivityItem(
            id: "upvote-post-1",
            act: .upvote,
            occurredAt: referenceDate,
            object: .post(samplePost())
        )
    }

    private func downvotePostItem() -> ActivityItem {
        ActivityItem(
            id: "downvote-post-1",
            act: .downvote,
            occurredAt: referenceDate,
            object: .post(samplePost())
        )
    }

    private func readPostItem() -> ActivityItem {
        ActivityItem(
            id: "read-post-1",
            act: .read,
            occurredAt: referenceDate,
            object: .post(samplePost())
        )
    }

    private func commentItem() -> ActivityItem {
        ActivityItem(
            id: "comment-comment-42",
            act: .comment,
            occurredAt: referenceDate,
            object: .comment(sampleComment())
        )
    }

    private func saveCommentItem() -> ActivityItem {
        ActivityItem(
            id: "save-comment-42",
            act: .save,
            occurredAt: referenceDate,
            object: .comment(sampleComment())
        )
    }

    private func samplePost() -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: "Notes from a weekend in the mountains",
            body: "A short trip report with a few photos from the ridge trail.",
            originalPostUrl: "https://lemmy.world/post/1",
            url: nil,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "hiking",
            communityActorId: "https://lemmy.world/c/hiking",
            serverCommunityId: 1,
            creatorPersonId: 7,
            creatorName: "ada",
            creatorActorId: "https://lemmy.world/u/ada",
            score: 248,
            numberOfComments: 19,
            voteStatus: 1,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            published: referenceDate.addingTimeInterval(-8 * 3600)
        )
    }

    private func sampleComment() -> ActivityCommentRow {
        ActivityCommentRow(
            id: 42,
            serverCommentId: 42,
            body: "Beautiful shot — the light on the ridge is unreal. What time of day was this?",
            score: 17,
            parentPostTitle: "Notes from a weekend in the mountains",
            communityName: "hiking",
            communityActorId: "https://lemmy.world/c/hiking",
            serverPostId: 1,
            published: referenceDate.addingTimeInterval(-7 * 3600)
        )
    }
}
