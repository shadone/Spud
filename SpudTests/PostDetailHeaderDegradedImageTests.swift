//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Coverage for the post-detail header's degraded image state.
///
/// When a post's full-resolution image can't load (slow network / offline) but
/// the cached thumbnail is already on screen, the header must keep the thumbnail
/// visible and surface the subtle "Low-res preview" pill — NOT cover the
/// thumbnail with the hard `ImageLoadFailureView`. The full failure plate is
/// reserved for the case where there's nothing at all to show.
@MainActor
struct PostDetailHeaderDegradedImageTests {
    private let width: CGFloat = 390

    /// Scripts a single `fetch(_:thumbnail:)` outcome for the header.
    private final class ScriptedService: ImageServiceType, @unchecked Sendable {
        enum Outcome {
            /// `.loading(thumbnail: image)` then `.failure` — a thumbnail shows,
            /// then the full image fails (the degraded case).
            case thumbnailThenFailure(UIImage)
            /// `.failure` with no thumbnail — nothing to show (hard failure).
            case failureNoThumbnail
            /// `.ready(image)` — the full image loads fine.
            case ready(UIImage)
        }

        private let outcome: Outcome
        init(_ outcome: Outcome) {
            self.outcome = outcome
        }

        func fetch(_: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
            let outcome = outcome
            return AsyncStream { continuation in
                switch outcome {
                case let .thumbnailThenFailure(image):
                    continuation.yield(.loading(thumbnail: image))
                    continuation.yield(.failure)
                case .failureNoThumbnail:
                    continuation.yield(.loading(thumbnail: nil))
                    continuation.yield(.failure)
                case let .ready(image):
                    continuation.yield(.loading(thumbnail: nil))
                    continuation.yield(.ready(image))
                }
                continuation.finish()
            }
        }
    }

    @Test
    func fullResFailsWithThumbnail_showsPillNotPlate() async {
        let cell = makeConfiguredCell(.thumbnailThenFailure(thumbnail()))
        await waitUntilRendered(cell, "low-res preview pill") {
            cell.isLowResPreviewPillVisibleForTesting
        }

        #expect(cell.postImageView.image != nil, "the cached thumbnail must stay on screen")
        #expect(cell.isLowResPreviewPillVisibleForTesting, "the degraded pill must be shown")
        #expect(
            !cell.isImageFailureViewVisibleForTesting,
            "the hard failure plate must not cover a visible thumbnail"
        )
    }

    @Test
    func fullResFailsWithoutThumbnail_showsPlateNotPill() async {
        let cell = makeConfiguredCell(.failureNoThumbnail)
        await waitUntilRendered(cell, "hard failure plate") {
            cell.isImageFailureViewVisibleForTesting
        }

        #expect(cell.isImageFailureViewVisibleForTesting, "the hard failure plate must be shown")
        #expect(
            !cell.isLowResPreviewPillVisibleForTesting,
            "no thumbnail to preview, so no degraded pill"
        )
    }

    @Test
    func fullResSucceeds_showsNeitherPlateNorPill() async {
        let cell = makeConfiguredCell(.ready(photo()))
        await waitUntilRendered(cell, "loaded full image") {
            cell.postImageView.image != nil
        }

        #expect(cell.postImageView.image != nil)
        #expect(!cell.isImageFailureViewVisibleForTesting)
        #expect(!cell.isLowResPreviewPillVisibleForTesting)
    }

    // MARK: - Harness

    private func makeConfiguredCell(_ outcome: ScriptedService.Outcome) -> PostDetailHeaderCell {
        let cell = PostDetailHeaderCell(style: .default, reuseIdentifier: nil)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        cell.tableView = table
        cell.isBeingConfigured = true
        cell.configure(with: makeViewModel(), imageService: ScriptedService(outcome))
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        return cell
    }

    /// Polls up to a generous 10s deadline until `isRendered` is true, laying the
    /// cell out each turn, then fails loudly if the terminal state never arrived.
    ///
    /// The cell drives its image load on an unstructured `@MainActor` `Task`
    /// (`configure` -> `loadPostImage`). Under Swift Testing's full-target
    /// parallel load, that Task competes with every other `@MainActor` async test
    /// for main-actor time, so a short fixed wall-clock budget can expire before
    /// it is ever scheduled — the historical flake (the give-up was silent, so
    /// the caller's `#expect` misreported a timeout as a state bug). The budget
    /// is therefore generous (the real render work is microseconds; it only needs
    /// to be scheduled), and a genuine failure to render still surfaces as a loud
    /// `Issue`. Mirrors `PendingPostSnapshotTests`' "await until rendered or fail
    /// loudly" precedent.
    private func waitUntilRendered(
        _ cell: PostDetailHeaderCell,
        _ description: String,
        isRendered: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(10)
        while !isRendered(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
            cell.layoutIfNeeded()
        }
        // One more turn so the terminal state's layout settles.
        await Task.yield()
        cell.layoutIfNeeded()
        if !isRendered() {
            Issue.record("Header cell never rendered within 10s: \(description)")
        }
    }

    private func makeViewModel() -> PostDetailHeaderViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService.ephemeral())
        return PostDetailHeaderViewModel(
            row: row(),
            appearance: appearance,
            postContentDetector: PostContentDetectorService()
        )
    }

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 150)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 150))
        }
    }

    private func thumbnail() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60)).image { context in
            UIColor.systemGray3.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
        }
    }

    private func row() -> PostDetailHeaderRow {
        PostDetailHeaderRow(
            id: 1,
            serverPostId: 1,
            title: "Photo post",
            body: "",
            originalPostUrl: "https://lemmy.world/post/1",
            url: "https://lemmy.world/pictrs/image/example.jpg",
            thumbnailUrl: "https://lemmy.world/pictrs/image/example-thumb.jpg",
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
            creatorActorId: "https://lemmy.world",
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
