//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUIKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots for the Activity timeline: the REAL composed rows (an
/// `ActivityActionHeaderView` over a reused `PostListPostCell` / `SearchCommentCell`,
/// not the old hand-rolled label stacks), the filter-chip bar, a populated
/// timeline, and the empty / offline / voted-first-run states.
///
/// Rows are built from a representative `PostListRow` / `ActivityCommentRow` fed
/// through the same view models the screen uses, so references are
/// device-independent (`.image(size:traits:)`) and free of DB / network.
/// All tests run light + dark; record on iPhone 17 Pro, iOS 26.3.1.
@MainActor
final class ActivitySnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - Composed post rows

    func test_postRow_upvoted() async {
        await assertCell(renderPostRow(item: upvotePostItem()))
    }

    func test_postRow_downvoted() async {
        await assertCell(renderPostRow(item: downvotePostItem()))
    }

    func test_postRow_read() async {
        await assertCell(renderPostRow(item: readPostItem()))
    }

    /// The composed post row at the largest accessibility text size, proving the
    /// reused feed cell + action header reflow rather than clip.
    func test_postRow_dynamicTypeXXXL() async {
        let cell = await renderPostRow(item: upvotePostItem())
        snapshotCell(
            cell,
            style: .light,
            testName: #function,
            line: #line,
            contentSize: .accessibilityExtraExtraExtraLarge
        )
    }

    // MARK: - Composed comment rows

    func test_commentRow_commented() async {
        await assertCell(renderCommentRow(item: commentItem(), comment: sampleComment()))
    }

    func test_commentRow_saved() async {
        await assertCell(renderCommentRow(item: saveCommentItem(), comment: sampleComment()))
    }

    // MARK: - Populated timeline

    /// A short interleaved timeline (post + comment + post), approximating the
    /// on-screen list without the async GRDB stream. Each row is measured and
    /// framed individually (the same per-cell measurement the row tests use), so
    /// the composite is deterministic - unlike letting a UIStackView re-measure
    /// embedded table cells.
    func test_timeline_populated() async {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let rows: [UIView] = await [
                renderPostRow(item: upvotePostItem()),
                renderCommentRow(item: commentItem(), comment: sampleComment()),
                renderPostRow(item: readPostItem()),
            ]
            let container = composeVertically(rows)
            assertContainer(container, style: style, testName: #function, line: #line)
        }
    }

    /// Measures each row at the device width and stacks them with explicit frames.
    private func composeVertically(_ views: [UIView]) -> UIView {
        let container = UIView()
        var y: CGFloat = 0
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = true
            let measureTarget: UIView = (view as? UITableViewCell)?.contentView ?? view
            view.frame = CGRect(x: 0, y: 0, width: width, height: 3000)
            view.layoutIfNeeded()
            let height = max(1, measureTarget.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height)
            view.frame = CGRect(x: 0, y: y, width: width, height: height)
            container.addSubview(view)
            y += height
        }
        container.frame = CGRect(x: 0, y: 0, width: width, height: y)
        return container
    }

    private func assertContainer(
        _ container: UIView,
        style: UIUserInterfaceStyle,
        testName: String,
        line: UInt
    ) {
        container.backgroundColor = .systemBackground
        container.tintColor = lemmyTeal
        container.layoutIfNeeded()
        assertSnapshot(
            matching: container,
            as: .image(size: container.bounds.size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    // MARK: - States

    func test_state_generalEmpty() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = ActivityStateContent.emptyConfiguration(filters: []).makeContentView()
            snapshotFixedHeight(view, height: 420, style: style, testName: #function, line: #line)
        }
    }

    func test_state_votedFirstRun() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = ActivityStateContent.emptyConfiguration(filters: [.vote]).makeContentView()
            snapshotFixedHeight(view, height: 320, style: style, testName: #function, line: #line)
        }
    }

    func test_state_offlineBanner() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            snapshotFixedHeight(offlineBanner(), height: 56, style: style, testName: #function, line: #line)
        }
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

    // MARK: - Row builders

    private func renderPostRow(item: ActivityItem) async -> ActivityPostRowCell {
        guard case let .post(row) = item.object else {
            fatalError("renderPostRow requires a post item")
        }
        let cell = ActivityPostRowCell(style: .default, reuseIdentifier: nil)
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground

        let viewModel = makePostViewModel(row: row)
        cell.postCell.configure(with: viewModel, imageService: ScriptedImageService([.failure]))
        cell.configure(item: item, postSummary: viewModel.accessibilityLabel, hint: viewModel.accessibilityHint)
        try? await Task.sleep(nanoseconds: 80_000_000)
        await Task.yield()
        return cell
    }

    private func renderCommentRow(item: ActivityItem, comment: ActivityCommentRow) -> ActivityCommentRowCell {
        let cell = ActivityCommentRowCell(style: .default, reuseIdentifier: nil)
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
        cell.configure(item: item, comment: comment, hint: "Opens the comment in its post")
        return cell
    }

    private func offlineBanner() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground

        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = ActivityStateContent.offlineBannerText
        label.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.plain()
        config.title = ActivityStateContent.offlineRetryTitle
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: - Snapshot harness

    private func assertCell(
        _ cell: UITableViewCell,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            snapshotCell(cell, style: style, testName: testName, line: line, contentSize: .large)
        }
    }

    private func snapshotCell(
        _ cell: UITableViewCell,
        style: UIUserInterfaceStyle,
        testName: String,
        line: UInt,
        contentSize: UIContentSizeCategory
    ) {
        let traitCollection = traits(style, contentSize: contentSize)
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 3000)
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
            as: .image(size: CGSize(width: width, height: height), traits: traitCollection),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    private func snapshotFixedHeight(
        _ view: UIView,
        height: CGFloat,
        style: UIUserInterfaceStyle,
        testName: String,
        line: UInt
    ) {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        container.backgroundColor = .systemBackground
        container.tintColor = lemmyTeal
        view.frame = container.bounds
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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

    private func traits(
        _ style: UIUserInterfaceStyle,
        contentSize: UIContentSizeCategory = .large
    ) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            UITraitCollection(preferredContentSizeCategory: contentSize),
        ])
    }

    // MARK: - Test data

    private let referenceDate = Date(timeIntervalSince1970: 1_751_000_000) // 2025-06-27

    private func upvotePostItem() -> ActivityItem {
        ActivityItem(id: "upvote-post-1", act: .upvote, occurredAt: referenceDate, object: .post(samplePost(voteStatus: 1)))
    }

    private func downvotePostItem() -> ActivityItem {
        ActivityItem(id: "downvote-post-1", act: .downvote, occurredAt: referenceDate, object: .post(samplePost(voteStatus: 0)))
    }

    private func readPostItem() -> ActivityItem {
        ActivityItem(id: "read-post-1", act: .read, occurredAt: referenceDate, object: .post(samplePost(isRead: true)))
    }

    private func commentItem() -> ActivityItem {
        ActivityItem(id: "comment-comment-42", act: .comment, occurredAt: referenceDate, object: .comment(sampleComment()))
    }

    private func saveCommentItem() -> ActivityItem {
        ActivityItem(id: "save-comment-42", act: .save, occurredAt: referenceDate, object: .comment(sampleComment()))
    }

    private func makePostViewModel(row: PostListRow) -> PostListPostViewModel {
        let preferences = PreferencesService()
        let appearance = AppearanceService(preferencesService: preferences)
        return PostListPostViewModel(
            row: row,
            appearance: appearance,
            postContentDetector: PostContentDetectorService()
        )
    }

    private func samplePost(voteStatus: Int64? = 1, isRead: Bool = false) -> PostListRow {
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
            voteStatus: voteStatus,
            isRead: isRead,
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
