//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Regression coverage for a post-detail body that collapses to a narrow column.
///
/// When the post body contains an inline image, `MarkdownBodyView` calls
/// `invalidateIntrinsicContentSize()` once the image finishes loading. The
/// header hosts the body in a stack whose alignment must keep the body pinned to
/// the full content width; otherwise the re-measure lets the body shrink to its
/// intrinsic (word-width) size and the whole body renders as a ~80pt column.
@MainActor
struct PostDetailHeaderBodyWidthTests {
    private let width: CGFloat = 390

    /// Returns a fixed image synchronously so an inline body image resolves to
    /// `.ready` immediately — deterministic, no network.
    private final class StubImageService: ImageServiceType, @unchecked Sendable {
        private let image: UIImage
        init(image: UIImage) {
            self.image = image
        }

        func fetch(_: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
            let image = image
            return AsyncStream { continuation in
                continuation.yield(.ready(image))
                continuation.finish()
            }
        }
    }

    @Test
    func bodyWithInlineImage_fillsCellWidth() async {
        let cell = await renderCell(
            body: """
                A reasonably long paragraph of body text that should wrap across the \
                full content width of the post-detail header rather than collapsing.

                ![](https://example.com/screenshot.png)

                More text after the image.
                """
        )

        let bodyWidth = cell.bodyView.frame.width
        #expect(
            bodyWidth > width - 40,
            "Post body collapsed to \(bodyWidth)pt instead of filling the cell width"
        )
    }

    @Test
    func bodyWithSpoileredImage_fillsCellWidth() async {
        // Mirrors the reported post: paragraphs followed by a spoiler whose only
        // child is an inline image.
        let cell = await renderCell(
            body: """
                Flying boats are fixed-wing aircraft with hulls like boats, allowing \
                them to land on water instead of runways.

                Here is a screenshot of where to find the spoiler button.

                ::: spoiler spoiler
                ![](https://hexbear.net/pictrs/image/example.png)
                :::
                """
        )

        let bodyWidth = cell.bodyView.frame.width
        #expect(
            bodyWidth > width - 40,
            "Post body collapsed to \(bodyWidth)pt instead of filling the cell width"
        )
    }

    // MARK: - Harness

    private func renderCell(body: String) async -> PostDetailHeaderCell {
        let cell = PostDetailHeaderCell(style: .default, reuseIdentifier: nil)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        cell.tableView = table
        cell.isBeingConfigured = true

        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 150)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 150))
        }
        cell.configure(
            with: makeViewModel(body: body),
            imageService: StubImageService(image: image)
        )

        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        cell.layoutIfNeeded()

        // Let the inline image's load Task drain and the resulting
        // invalidateIntrinsicContentSize settle into a fresh layout pass.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
            cell.layoutIfNeeded()
        }

        return cell
    }

    private func makeViewModel(body: String) -> PostDetailHeaderViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        return PostDetailHeaderViewModel(
            row: row(body: body),
            appearance: appearance,
            postContentDetector: PostContentDetectorService()
        )
    }

    private func row(body: String) -> PostDetailHeaderRow {
        PostDetailHeaderRow(
            id: 1,
            serverPostId: 1,
            title: "Flying Boats",
            body: body,
            originalPostUrl: "https://hexbear.net/post/1",
            url: nil,
            thumbnailUrl: nil,
            imageWidth: nil,
            imageHeight: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "traaaaaaannnnnnnnnns",
            communityActorId: "https://hexbear.net/c/traaaaaaannnnnnnnnns",
            serverCommunityId: 1,
            creatorName: "peanutbuttercupola",
            creatorPersonId: 1,
            creatorActorId: "https://hexbear.net",
            score: 123,
            numberOfComments: 45,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            published: Date(timeIntervalSinceNow: -5 * 3600)
        )
    }
}
