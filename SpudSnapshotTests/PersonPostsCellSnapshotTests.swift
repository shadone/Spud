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

/// Locks in that the person profile's POSTS tab renders with the canonical feed
/// cell `PostListPostCell` (vote arrows, saved badge, community line, score /
/// comments / age metadata) — the explicit goal of switching the profile off the
/// lightweight `SearchPostCell` onto the feed cell.
///
/// The profile builds each post row exactly like the feed: a `PostListRow`
/// (sourced from the persisted post import) fed through `PostListPostViewModel`.
/// This renders that cell straight from a representative row, so the reference is
/// device-independent (`.image(size:traits:)`) and free of any DB / network.
@MainActor
final class PersonPostsCellSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    /// A representative post by the profile's author: upvoted and saved, with the
    /// community line — the state the lightweight search cell could not show and
    /// the feed cell now does on the profile.
    func test_personPost_feedCell() async {
        await assertCell(profileRow(voteStatus: 1, isSaved: true))
    }

    /// A neutral, unsaved post — the plain baseline.
    func test_personPost_neutral() async {
        await assertCell(profileRow(voteStatus: nil, isSaved: false))
    }

    // MARK: - Rendering

    private func assertCell(
        _ row: PostListRow,
        testName: String = #function,
        line: UInt = #line
    ) async {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = await renderCell(row: row)
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func renderCell(row: PostListRow) async -> PostListPostCell {
        let cell = PostListPostCell(style: .default, reuseIdentifier: nil)
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground

        cell.configure(with: makeViewModel(row: row), imageService: ScriptedImageService([.failure]))
        try? await Task.sleep(nanoseconds: 80_000_000)
        await Task.yield()
        return cell
    }

    private func snapshot(
        _ cell: PostListPostCell,
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

        assertSnapshot(
            matching: cell.contentView,
            as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    private func makeViewModel(row: PostListRow) -> PostListPostViewModel {
        let preferences = PreferencesService()
        let appearance = AppearanceService(preferencesService: preferences)
        return PostListPostViewModel(
            row: row,
            appearance: appearance,
            postContentDetector: PostContentDetectorService()
        )
    }

    private func profileRow(voteStatus: Int64?, isSaved: Bool) -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: "Notes from a weekend in the mountains",
            body: "A short trip report with a few photos.",
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
            isRead: false,
            isSaved: isSaved,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            published: Date(timeIntervalSinceNow: -8 * 3600)
        )
    }
}
