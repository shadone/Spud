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

/// Snapshots of the post-detail header cell across its content and image-load
/// states: a loaded image, the failure plate, an in-flight retry (spinner
/// plate), a text-only post, an external-link preview, and a video poster —
/// each in light and dark.
///
/// The header is rendered straight from a `PostDetailHeaderRow` fixture and a
/// scripted image service, with no database or network: the view model is a
/// pure transform of the row, and `ScriptedImageService` drives the image
/// outcome deterministically. The cell is hosted on a detached stub table (so
/// its width-based image sizing resolves) and rendered at a fixed width and
/// pinned display scale, so the references are device-independent.
@MainActor
final class PostDetailHeaderSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    /// The cell's `tableView` reference is weak; hold the stub tables so they
    /// outlive the image-sizing that reads their width.
    private var stubTables: [UITableView] = []

    // MARK: - States

    func test_image_ready() async {
        await assertHeader(
            row: row(url: imageUrl),
            imageService: ScriptedImageService([.ready(photo())])
        )
    }

    func test_image_failure() async {
        await assertHeader(
            row: row(url: imageUrl),
            imageService: ScriptedImageService([.failure])
        )
    }

    func test_image_loading() async {
        // The loading placeholder hosts a live `UIActivityIndicatorView` whose fade
        // phase advances with wall-clock time and cannot be frozen from the test
        // (the spinner re-arms its display-link animation when reparented into the
        // render window). Under full-plan load the captured phase jitters by one
        // blade — a ~20x20px, sub-0.03% pixel difference — so tolerate it with a
        // precision floor rather than asserting an exact animating frame.
        await assertHeader(
            row: row(url: imageUrl),
            imageService: ScriptedImageService([.loadingForever]),
            precision: 0.98
        )
    }

    func test_image_thumbnail() async {
        await assertHeader(
            row: row(url: imageUrl),
            imageService: ScriptedImageService([.loadingThumbnail(thumbnailPhoto())]),
            precision: 0.98
        )
    }

    func test_image_loading_reserved() async {
        // The service already knows the image's size (the post list fetched its
        // thumbnail), so the loading placeholder reserves the exact aspect-ratio
        // height up front rather than the neutral default — the image won't
        // resize the row when it appears.
        await assertHeader(
            row: row(url: imageUrl),
            imageService: ScriptedImageService(
                [.loadingForever],
                knownSize: CGSize(width: 1200, height: 800)
            ),
            precision: 0.98
        )
    }

    func test_image_loading_reserved_from_metadata() async {
        // The server reported the image's dimensions (`image_details`), so the
        // placeholder reserves the exact height even on a cold path where the
        // image service has nothing cached. A portrait image also exercises the
        // max-height clamp.
        await assertHeader(
            row: row(url: imageUrl, imageWidth: 800, imageHeight: 1200),
            imageService: ScriptedImageService([.loadingForever]),
            precision: 0.98
        )
    }

    func test_image_retrying() async {
        await assertHeader(
            row: row(url: imageUrl),
            imageService: ScriptedImageService([.failure, .loadingForever]),
            driveRetry: true
        )
    }

    func test_text() async {
        await assertHeader(
            row: row(url: nil),
            imageService: ScriptedImageService([.failure])
        )
    }

    func test_link() async {
        await assertHeader(
            row: row(
                url: "https://example.com/the-quiet-web",
                thumbnailUrl: "https://example.com/og.jpg",
                urlEmbedTitle: "The quiet web",
                urlEmbedDescription: "A short essay on small, personal corners of the internet."
            ),
            imageService: ScriptedImageService([.ready(photo())])
        )
    }

    func test_video() async {
        await assertHeader(
            row: row(
                url: "https://lemmy.world/pictrs/video/clip.mp4",
                thumbnailUrl: "https://lemmy.world/pictrs/image/poster.jpg"
            ),
            imageService: ScriptedImageService([.ready(photo())])
        )
    }

    // MARK: - Logic

    func test_isImageBlurred_logic() {
        // Blurred when all three conditions are true.
        let nsfw = row(url: imageUrl, isNsfw: true)
        let blurredVM = makeViewModel(row: nsfw, blurNsfw: true, isRevealed: false)
        XCTAssertTrue(blurredVM.isImageBlurred, "NSFW + blurNsfw + unrevealed => blurred")

        // Not blurred when the preference is off.
        let prefOffVM = makeViewModel(row: nsfw, blurNsfw: false, isRevealed: false)
        XCTAssertFalse(prefOffVM.isImageBlurred, "blurNsfw=false => not blurred")

        // Not blurred after the user reveals.
        let revealedVM = makeViewModel(row: nsfw, blurNsfw: true, isRevealed: true)
        XCTAssertFalse(revealedVM.isImageBlurred, "isRevealed => not blurred")

        // Not blurred when the post is not NSFW.
        let clean = row(url: imageUrl, isNsfw: false)
        let cleanVM = makeViewModel(row: clean, blurNsfw: true, isRevealed: false)
        XCTAssertFalse(cleanVM.isImageBlurred, "non-NSFW post => not blurred")
    }

    // MARK: - Degraded (low-res preview)

    /// The degraded state: the full-resolution image failed to load but the
    /// cached thumbnail is on screen, so the header keeps the thumbnail and
    /// overlays the subtle "Low-res preview · retry" pill instead of the hard
    /// failure plate. The pill is a `UIVisualEffectView` blur, which only renders
    /// when drawn through the key window — so this uses the
    /// `drawHierarchyInKeyWindow: true` strategy (like the NSFW blur test) rather
    /// than the offscreen `.image(size:traits:)` path.
    func test_image_lowResPreview() async {
        let cell = await renderCell(
            row: row(url: imageUrl),
            imageService: ScriptedImageService([.loadingThumbnailThenFailure(thumbnailPhoto())]),
            driveRetry: false
        )

        for style in [UIUserInterfaceStyle.light, UIUserInterfaceStyle.dark] {
            snapshotBlur(cell, style: style)
        }
    }

    // MARK: - NSFW blur

    /// A blurred NSFW header cell. UIVisualEffectView only renders when drawn
    /// through the key window, so this test uses `drawHierarchyInKeyWindow: true`
    /// rather than the offscreen `.image(size:traits:)` path used by other header
    /// tests.
    func test_image_nsfwBlurred() async {
        let cell = await renderCell(
            row: row(url: imageUrl, isNsfw: true),
            imageService: ScriptedImageService([.ready(photo())]),
            driveRetry: false,
            blurNsfw: true,
            isRevealed: false
        )

        for style in [UIUserInterfaceStyle.light, UIUserInterfaceStyle.dark] {
            snapshotBlur(cell, style: style)
        }
    }

    // MARK: - Rendering

    private func assertHeader(
        row: PostDetailHeaderRow,
        imageService: @autoclosure () -> ImageServiceType,
        driveRetry: Bool = false,
        precision: Float = 1,
        testName: String = #function,
        line: UInt = #line
    ) async {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = await renderCell(
                row: row,
                imageService: imageService(),
                driveRetry: driveRetry
            )
            snapshot(cell, style: style, precision: precision, testName: testName, line: line)
        }
    }

    private func renderCell(
        row: PostDetailHeaderRow,
        imageService: ImageServiceType,
        driveRetry: Bool,
        blurNsfw: Bool = false,
        isRevealed: Bool = false
    ) async -> PostDetailHeaderCell {
        let cell = PostDetailHeaderCell(style: .default, reuseIdentifier: nil)
        // Pin the accent on the snapshot root: the `.image` strategy reparents
        // `contentView` into a fresh window, so without its own tintColor it
        // would inherit the window's system blue instead of the brand teal that
        // the actions and vote arrows follow at runtime.
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        // The cell is transparent and sits on the table's background at runtime;
        // give the snapshot the same opaque backdrop so `label`-colored text
        // stays legible (white-on-transparent would vanish in dark mode).
        cell.contentView.backgroundColor = .systemBackground

        let table = UITableView(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        stubTables.append(table)
        cell.tableView = table
        cell.isBeingConfigured = true

        cell.configure(
            with: makeViewModel(row: row, blurNsfw: blurNsfw, isRevealed: isRevealed),
            imageService: imageService
        )
        await settle()

        if driveRetry {
            findRetryButton(in: cell.contentView)?.sendActions(for: .primaryActionTriggered)
            await settle()
        }

        return cell
    }

    /// - Parameter precision: fraction of pixels that must match (1 = exact). Loosened
    ///   only for the loading-spinner tests, whose `UIActivityIndicatorView` fade phase
    ///   is inherently non-deterministic; kept exact (the default) everywhere else.
    private func snapshot(
        _ cell: PostDetailHeaderCell,
        style: UIUserInterfaceStyle,
        precision: Float = 1,
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
            as: .image(precision: precision, size: CGSize(width: width, height: height), traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    /// Snapshot path for views containing `UIVisualEffectView`: blur only renders
    /// when the view hierarchy is connected to the key window. Uses
    /// `drawHierarchyInKeyWindow: true` so the blur effect is visible in the ref.
    private func snapshotBlur(
        _ cell: PostDetailHeaderCell,
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
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
            as: .image(
                drawHierarchyInKeyWindow: true,
                size: CGSize(width: width, height: height),
                traits: traits(style)
            ),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    /// Let the cell's image-load Task drain its scripted stream and apply the
    /// resulting layout before we measure and snapshot.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
        await Task.yield()
    }

    private func findRetryButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == "imageLoadFailureRetry" {
            return button
        }
        for subview in view.subviews {
            if let found = findRetryButton(in: subview) {
                return found
            }
        }
        return nil
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    private func makeViewModel(
        row: PostDetailHeaderRow,
        blurNsfw: Bool = false,
        isRevealed: Bool = false
    ) -> PostDetailHeaderViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        return PostDetailHeaderViewModel(
            row: row,
            appearance: appearance,
            postContentDetector: PostContentDetectorService(),
            blurNsfw: blurNsfw,
            isRevealed: isRevealed
        )
    }

    // MARK: - Fixtures

    /// A pictrs-style image url whose extension makes the content detector
    /// classify the post as an image.
    private let imageUrl = "https://lemmy.world/pictrs/image/lake.jpg"

    /// A landscape solid-color image standing in for a loaded photo. Fixed size
    /// so its aspect ratio (and therefore the header's image height) is stable.
    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
    }

    /// A small, lower-detail stand-in for a pict-rs thumbnail, with the same 3:2
    /// aspect as `photo()` so swapping to the full image wouldn't change the
    /// header height. A flat fill is enough to show it fills the image's place
    /// under the spinner.
    private func thumbnailPhoto() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).image { context in
            UIColor.systemGray3.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        }
    }

    private func row(
        url: String?,
        thumbnailUrl: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        urlEmbedTitle: String? = nil,
        urlEmbedDescription: String? = nil,
        isNsfw: Bool = false
    ) -> PostDetailHeaderRow {
        PostDetailHeaderRow(
            id: 1,
            serverPostId: 1,
            title: "A scenic mountain lake at golden hour",
            body: "Caught this on a hike last weekend — the light only held for a couple of minutes.",
            originalPostUrl: "https://lemmy.world/post/1",
            url: url,
            thumbnailUrl: thumbnailUrl,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            urlEmbedTitle: urlEmbedTitle,
            urlEmbedDescription: urlEmbedDescription,
            altText: nil,
            communityName: "photography",
            communityTitle: "Photography",
            communityActorId: "https://lemmy.world/c/photography",
            serverCommunityId: 1,
            creatorName: "ansel",
            creatorPersonId: 1,
            creatorActorId: "https://lemmy.world",
            score: 1234,
            numberOfComments: 56,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: isNsfw,
            published: Date(timeIntervalSinceNow: -5 * 3600)
        )
    }
}
