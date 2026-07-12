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

/// Snapshots of the feed cell `PostListPostCell` across its content and state
/// matrix: text / image / link / video posts; read vs unread; upvoted /
/// downvoted / neutral; saved; the moderation badges (locked, removed,
/// featured, NSFW-as-removed); and the compact density variant — each in light
/// and dark.
///
/// The cell is rendered straight from a `PostListRow` fixture and a deterministic
/// image service, with no database or network: the view model is a pure
/// transform of the row, and `StaticImageService` / `ScriptedImageService` drive
/// the thumbnail outcome. Each render builds a fresh `PreferencesService` (so a
/// density override on one method doesn't bleed into another) and renders the
/// `contentView` at a fixed feed width and pinned display scale, so the
/// references are device-independent.
@MainActor
final class PostListPostCellSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - States

    func test_text() async {
        await assertCell(row(url: nil))
    }

    func test_image() async {
        await assertCell(
            row(url: imageUrl, thumbnailUrl: imageUrl),
            imageService: StaticImageService()
        )
    }

    func test_image_failure() async {
        await assertCell(
            row(url: imageUrl, thumbnailUrl: imageUrl),
            imageService: ScriptedImageService([.failure])
        )
    }

    func test_link() async {
        await assertCell(
            row(
                url: "https://mozilla.org/the-quiet-web",
                thumbnailUrl: "https://mozilla.org/og.jpg",
                body: "A short essay on small, personal corners of the internet.",
                urlEmbedTitle: "The quiet web",
                urlEmbedDescription: "Small, personal corners of the internet."
            ),
            imageService: StaticImageService()
        )
    }

    func test_video() async {
        await assertCell(
            row(
                url: "https://lemmy.world/pictrs/video/clip.mp4",
                thumbnailUrl: "https://lemmy.world/pictrs/image/poster.jpg"
            ),
            imageService: StaticImageService()
        )
    }

    func test_read() async {
        await assertCell(row(url: nil, isRead: true))
    }

    func test_unread() async {
        await assertCell(row(url: nil, isRead: false))
    }

    func test_upvoted() async {
        await assertCell(row(url: nil, voteStatus: 1))
    }

    func test_downvoted() async {
        await assertCell(row(url: nil, voteStatus: 0))
    }

    func test_neutral() async {
        await assertCell(row(url: nil, voteStatus: nil))
    }

    func test_saved() async {
        await assertCell(row(url: nil, isSaved: true))
    }

    func test_locked() async {
        await assertCell(row(url: nil, isLocked: true))
    }

    func test_removed() async {
        await assertCell(row(url: nil, isRemoved: true))
    }

    func test_unavailableBadge() async {
        await assertCell(row(url: nil, isRemoved: false, isDeleted: false, isUnavailable: true))
    }

    func test_featured() async {
        await assertCell(row(url: nil, isFeaturedCommunity: true))
    }

    /// NSFW posts have no dedicated cell badge; an instance-removed NSFW post
    /// surfaces through the removed marker. This pins the removed-marker look on
    /// a representative adult-content title.
    func test_nsfw_removed() async {
        await assertCell(
            row(
                url: nil,
                title: "[NSFW] Adults-only photo set",
                isRemoved: true
            )
        )
    }

    func test_compactDensity() async {
        await assertCell(
            row(url: imageUrl, thumbnailUrl: imageUrl),
            imageService: StaticImageService(),
            density: .compact
        )
    }

    // MARK: - Author status

    /// A post by a site-suspended author: the feed leads the metadata run with a
    /// single low-noise red `person.fill.xmark` marker.
    func test_authorSuspended() async {
        await assertCell(row(url: nil, isCreatorSiteBanned: true))
    }

    /// A post by an author banned from this community shows the same marker (the
    /// list doesn't distinguish site-ban from community-ban — the detail does).
    func test_authorCommunityBanned() async {
        await assertCell(row(url: nil, isCreatorBannedFromCommunity: true))
    }

    /// A post by an admin/mod author shows NO marker — the feed stays quiet for
    /// benign roles, so this must render identically to an ordinary text post.
    func test_authorAdminMod() async {
        await assertCell(row(url: nil, isCreatorModerator: true, isCreatorAdmin: true))
    }

    // MARK: - Fold (arrows hidden)

    func test_fold_upvoted() async {
        await assertCell(row(url: nil, voteStatus: 1), showVoteButtons: false)
    }

    func test_fold_downvoted() async {
        await assertCell(row(url: nil, voteStatus: 0), showVoteButtons: false)
    }

    func test_fold_neutral() async {
        await assertCell(row(url: nil, voteStatus: nil), showVoteButtons: false)
    }

    // MARK: - Subtitle wrapping

    /// A long community handle pushes the subtitle past the row width, so it
    /// wraps after the community name: the handle stays on the first line and
    /// the fixed-width metadata block (score, comments, age) drops to the
    /// second, kept intact rather than split or elided.
    func test_longCommunityName_wraps() async {
        await assertCell(
            row(
                url: nil,
                communityName: "urbanphotographyandstreetscenes",
                communityActorId: "https://feddit.someverylonghost.example/c/urbanphotographyandstreetscenes"
            )
        )
    }

    /// A short handle plus metadata fits on a single line, so the subtitle does
    /// not wrap — locking the no-wrap path the long-name case can't cover.
    func test_shortCommunityName_singleLine() async {
        await assertCell(
            row(
                url: nil,
                communityName: "art",
                communityActorId: "https://x.io/c/art"
            )
        )
    }

    // MARK: - Cross-post affordance

    /// The primary of two collapsed cross-post siblings (`CrossPostGrouper`)
    /// shows the "Also in ..." affordance line under the subtitle. The default
    /// empty `crossPostSiblingCommunityNames` used by every other test in this
    /// file keeps `crossPostLabel` hidden and out of the layout — this is the
    /// one case that exercises it present.
    func test_crossPostAffordance() async {
        await assertCell(
            row(url: nil),
            crossPostSiblingCommunityNames: ["photography", "pics"]
        )
    }

    // MARK: - Rendering

    private func assertCell(
        _ row: PostListRow,
        imageService: @autoclosure () -> ImageServiceType = ScriptedImageService([.failure]),
        density: PostDensity = .comfortable,
        showVoteButtons: Bool = true,
        crossPostSiblingCommunityNames: [String] = [],
        testName: String = #function,
        line: UInt = #line
    ) async {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = await renderCell(
                row: row,
                imageService: imageService(),
                density: density,
                showVoteButtons: showVoteButtons,
                crossPostSiblingCommunityNames: crossPostSiblingCommunityNames
            )
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func renderCell(
        row: PostListRow,
        imageService: ImageServiceType,
        density: PostDensity,
        showVoteButtons: Bool = true,
        crossPostSiblingCommunityNames: [String] = []
    ) async -> PostListPostCell {
        let cell = PostListPostCell(style: .default, reuseIdentifier: nil)
        // Pin the accent on the snapshot root: the `.image` strategy reparents
        // `contentView` into a fresh window, so without its own tintColor it
        // would inherit the window's system blue. The active upvote tint is
        // resolved from the theme, but pinning here keeps the snapshot root's
        // inherited tint consistent with the runtime feed.
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        // The cell is transparent and sits on the table's background at runtime;
        // give the snapshot the same opaque backdrop so `label`-colored text
        // stays legible (white-on-transparent would vanish in dark mode).
        cell.contentView.backgroundColor = .systemBackground

        cell.configure(
            with: makeViewModel(
                row: row,
                density: density,
                showVoteButtons: showVoteButtons,
                crossPostSiblingCommunityNames: crossPostSiblingCommunityNames
            ),
            imageService: imageService
        )
        await settle()

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

    /// Let the cell's thumbnail-load Task drain its scripted stream and apply the
    /// resulting layout before we measure and snapshot.
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

    private func makeViewModel(
        row: PostListRow,
        density: PostDensity,
        showVoteButtons: Bool = true,
        crossPostSiblingCommunityNames: [String] = []
    ) -> PostListPostViewModel {
        // A fresh, private UserDefaults suite per render so preference-backed
        // layout gates read their canonical defaults, isolated from the sim's
        // persisted state and from other tests. `thumbnailPosition` reads its
        // `.left` default from the clean suite; `postDensity`/`showVoteButtons`
        // are per-test inputs (some tests render with vote buttons hidden).
        let preferences = SnapshotPreferences.ephemeral()
        preferences.postDensity = density
        preferences.showVoteButtons = showVoteButtons
        let appearance = AppearanceService(preferencesService: preferences)
        return PostListPostViewModel(
            row: row,
            appearance: appearance,
            postContentDetector: PostContentDetectorService(),
            crossPostSiblingCommunityNames: crossPostSiblingCommunityNames
        )
    }

    // MARK: - Fixtures

    /// A pictrs-style image url whose `.jpg` extension makes the content detector
    /// classify the post as an image.
    private let imageUrl = "https://lemmy.world/pictrs/image/lake.jpg"

    private func row(
        url: String?,
        thumbnailUrl: String? = nil,
        title: String = "A scenic mountain lake at golden hour",
        body: String? = nil,
        urlEmbedTitle: String? = nil,
        urlEmbedDescription: String? = nil,
        communityName: String = "photography",
        communityActorId: String = "https://lemmy.world/c/photography",
        voteStatus: Int64? = nil,
        isRead: Bool = false,
        isSaved: Bool = false,
        isRemoved: Bool = false,
        isLocked: Bool = false,
        isFeaturedCommunity: Bool = false,
        isFeaturedLocal: Bool = false,
        isDeleted: Bool = false,
        isUnavailable: Bool = false,
        isNsfw: Bool = false,
        isCreatorModerator: Bool = false,
        isCreatorAdmin: Bool = false,
        isCreatorBannedFromCommunity: Bool = false,
        isCreatorSiteBanned: Bool = false
    ) -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: title,
            body: body,
            originalPostUrl: "https://lemmy.world/post/1",
            url: url,
            thumbnailUrl: thumbnailUrl,
            urlEmbedTitle: urlEmbedTitle,
            urlEmbedDescription: urlEmbedDescription,
            altText: nil,
            communityName: communityName,
            communityActorId: communityActorId,
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: "ansel",
            creatorActorId: "https://lemmy.world/u/ansel",
            score: 1234,
            numberOfComments: 56,
            voteStatus: voteStatus,
            isRead: isRead,
            isSaved: isSaved,
            isRemoved: isRemoved,
            isLocked: isLocked,
            isFeaturedCommunity: isFeaturedCommunity,
            isFeaturedLocal: isFeaturedLocal,
            isDeleted: isDeleted,
            isUnavailable: isUnavailable,
            isNsfw: isNsfw,
            isCreatorModerator: isCreatorModerator,
            isCreatorAdmin: isCreatorAdmin,
            isCreatorBannedFromCommunity: isCreatorBannedFromCommunity,
            isCreatorSiteBanned: isCreatorSiteBanned,
            published: Date(timeIntervalSinceNow: -5 * 3600)
        )
    }
}
