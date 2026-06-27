//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Regression coverage for the post-detail header image flickering on every vote.
///
/// Voting on a post optimistically updates the GRDB row, which re-runs the
/// header cell provider and calls `configure(...)` again with a new view model
/// carrying the same media but a changed vote/score. The cell must not restart
/// the image load on that reconfigure: re-running it clears `postImageView.image`
/// to a gray loading placeholder and then repaints the cached image
/// near-instantly, which reads as a flicker. When the post's media is unchanged,
/// the displayed image must stay in place across `configure`.
@MainActor
struct PostDetailHeaderImageReuseTests {
    private let width: CGFloat = 390

    /// Returns a fixed image synchronously so the post image resolves to `.ready`
    /// immediately — deterministic, no network.
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
    func voteReconfigure_keepsLoadedImage() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 150)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 150))
        }
        let imageService = StubImageService(image: image)

        let cell = PostDetailHeaderCell(style: .default, reuseIdentifier: nil)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        cell.tableView = table
        // Suppress tableView.begin/endUpdates on the delegate-less stub table.
        cell.isBeingConfigured = true

        // First render: an image post with no vote. Drain the load task so the
        // image arrives and is painted into the image view.
        cell.configure(with: makeViewModel(voteStatus: nil), imageService: imageService)
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        await drain(cell)
        #expect(cell.postImageView.image != nil, "Post image never loaded on first configure")

        // Simulate an optimistic upvote: the cell is reconfigured in place with
        // the same media but a changed vote. The already-loaded image must NOT be
        // cleared (clearing it and repainting is the flicker).
        cell.configure(with: makeViewModel(voteStatus: 1), imageService: imageService)
        #expect(
            cell.postImageView.image != nil,
            "Voting cleared the already-loaded post image (flicker)"
        )
    }

    @Test
    func voteReconfigure_keepsBodyLinkPreviewCards() {
        let imageService = StubImageService(image: UIImage())

        let cell = PostDetailHeaderCell(style: .default, reuseIdentifier: nil)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        cell.tableView = table
        // Suppress tableView.begin/endUpdates on the delegate-less stub table.
        cell.isBeingConfigured = true

        // A body with a link produces one preview card below the body.
        let body = "Check out [this article](https://example.com/article)."
        cell.configure(with: makeViewModel(voteStatus: nil, body: body), imageService: imageService)
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        cell.layoutIfNeeded()

        let card = cell.linkPreviewsStackView.arrangedSubviews.first
        #expect(card != nil, "Body link-preview card was never built on first configure")

        // Voting reconfigures with the same body links; the card must NOT be torn
        // down and rebuilt (which flickers and re-fetches its embed).
        cell.configure(with: makeViewModel(voteStatus: 1, body: body), imageService: imageService)
        #expect(
            cell.linkPreviewsStackView.arrangedSubviews.first === card,
            "Voting rebuilt the body link-preview card (flicker + redundant embed fetch)"
        )
    }

    // MARK: - Harness

    /// Polls until the post image's load Task paints the image, or gives up after
    /// 2s. Condition-based so it returns as soon as the (synchronous) stub image
    /// arrives instead of always burning the full budget; the caller's
    /// `#expect` is the failure point if it never renders.
    private func drain(_ cell: PostDetailHeaderCell) async {
        let deadline = Date().addingTimeInterval(2)
        while cell.postImageView.image == nil, Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
            cell.layoutIfNeeded()
        }
    }

    private func makeViewModel(voteStatus: Int64?, body: String = "") -> PostDetailHeaderViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        return PostDetailHeaderViewModel(
            row: row(voteStatus: voteStatus, body: body),
            appearance: appearance,
            postContentDetector: PostContentDetectorService()
        )
    }

    private func row(voteStatus: Int64?, body: String = "") -> PostDetailHeaderRow {
        PostDetailHeaderRow(
            id: 1,
            serverPostId: 1,
            title: "Photo post",
            body: body,
            originalPostUrl: "https://lemmy.world/post/1",
            url: "https://lemmy.world/pictrs/image/example.jpg",
            thumbnailUrl: nil,
            imageWidth: 300,
            imageHeight: 150,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "news",
            communityActorId: "https://lemmy.world/c/news",
            serverCommunityId: 1,
            creatorName: "tony",
            creatorPersonId: 1,
            creatorInstanceActorId: "https://lemmy.world",
            score: 123,
            numberOfComments: 45,
            voteStatus: voteStatus,
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
