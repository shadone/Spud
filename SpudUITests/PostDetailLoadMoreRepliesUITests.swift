//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import XCTest

/// Signed-out iPhone UITest exercising the "load more replies" tap end-to-end: a
/// comment thread that arrives truncated (the parent's `child_count` exceeds the
/// descendants present in the initial fetch) renders a "N more replies"
/// placeholder row, tapping it fetches the missing subtree via the neutral
/// `parent_id`-scoped `getComments`, and the observation splices the real
/// comments in over the placeholder.
///
/// ## Why the FIRST top-level thread is entirely stripped
///
/// The fixture (`comment-list-1549703-Hot-truncated.json`) is
/// `comment-list-1549703-Hot.json` with every descendant of comment 1773479 (the
/// thread's first root, 14 comments) removed, while 1773479's own
/// `counts.child_count` stays 15 — the same shape a v3/v4 server would return if
/// this subtree were paginated away. `CommentImporter.upsertComments` flags any
/// comment whose advertised `child_count` exceeds its present descendants and
/// inserts a "load more" placeholder immediately after it
/// (`LemmyCommentImportHelper.findCommentsWithMissingChildren`); because 1773479
/// is the very first depth-first-flattened root, its placeholder becomes the
/// SECOND comment row (right after the post header's first comment), reachable
/// with no scrolling. `comment-list-parent-1773479.json` is the corresponding
/// `parent_id=1773479` response — 1773479 plus its 14 original descendants,
/// unmodified — which `LemmyService.fetchMoreComments` requests on tap and
/// `spliceMoreComments` threads in over the placeholder.
///
/// ## Why signed-out
///
/// Loading more replies needs no authentication (a plain `getComments` fetch),
/// so this mirrors the base `SpudUITests` signed-out browse setup rather than
/// seeding an account.
///
/// SpudUITests target stays at Swift 5 until SBTUITestTunnelClient supports
/// strict concurrency.
class PostDetailLoadMoreRepliesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        // Device orientation is simulator-hardware state that survives
        // ResetFilesystem and can leak from an earlier suite run.
        XCUIDevice.shared.orientation = .portrait

        app = SBTUITunneledApplication()
        let launchOptions: [String] = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            // The App Group AppDatabase survives SBT's ResetFilesystem; wipe it so a
            // signed-in account left by an alphabetically-earlier suite can't make
            // this suite land signed in.
            AppLaunchArgument.wipeAppDatabase.rawValue,
            AppLaunchArgument.seedSignedOutDefaultAccount.rawValue,
        ]
        app.launchTunnel(withOptions: launchOptions) {
            self.app.monitorRequests(matching: SBTRequestMatch(url: ".*"))

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*"),
                response: SBTStubResponse(response: "", returnCode: 500)
            )

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "https://.*/pictrs/image/.*",
                    method: "GET"
                ),
                response: SBTStubResponse(
                    response: [
                        "image": "tv-pattern",
                    ],
                    contentType: "application/vnd.info.ddenis.spud.image+json"
                )
            )

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/post/list",
                    query: ["type_=All", "sort=Hot"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-list-all-hot.json")
            )

            // The initial comment fetch — TRUNCATED: comment 1773479's whole
            // subtree is missing even though its `child_count` (15) says
            // otherwise, so the importer renders a "15 more replies" placeholder
            // right after it. See the class doc for why this fixture, not the
            // shared `comment-list-1549703-Hot.json`.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/comment/list",
                    query: ["post_id=1549703", "sort=Hot"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "comment-list-1549703-Hot-truncated.json")
            )

            // Tapping the placeholder fires `getCommentsNeutral(parentId: 1773479, ...)`,
            // which on a v3 backend sends `parent_id` (no `post_id`, no `max_depth`) --
            // see `LemmyApi+GetCommentsNeutral.getCommentsNeutralV3(parentId:sort:)`.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/comment/list",
                    query: ["parent_id=1773479", "sort=Hot"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "comment-list-parent-1773479.json")
            )
        }
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait

        let allRequestUrls = app.monitoredRequestsFlushAll().map { request in
            let httpMethod = request.request!.httpMethod!
            let url = request.request!.url!.absoluteString
            return " - \(httpMethod) \(url)"
        }
        .joined(separator: "\n")
        print("### Network requests intercepted during the test:\n\(allRequestUrls)")
    }

    /// Tapping the "15 more replies" placeholder fetches and splices comment
    /// 1773479's subtree in place: the placeholder row disappears and its first
    /// child's body text appears in its place, proving the tap → fetch → splice
    /// → observation-driven re-render path end to end.
    func test_tapLoadMoreReplies_expandsSubtree() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "Feed should load")
        firstCell.tap()

        let detailHeaderCell = app.cells["postDetailHeader"]
        XCTAssertTrue(
            detailHeaderCell.waitForExistence(timeout: 10),
            "Post detail should be visible after selecting a post"
        )

        // Comment 1773479 (the truncated thread's root) renders first, and its
        // "load more" placeholder is the very next row -- no scrolling needed.
        let firstComment = app.cell(containing: "Nunc sagittis nulla tempor, luctus lectus a, molestie nisl")
        XCTAssertTrue(firstComment.waitForExistence(timeout: 10), "The truncated thread's root comment should render")

        let loadMoreRow = app.cell(containing: "15 more replies")
        XCTAssertTrue(
            loadMoreRow.waitForExistence(timeout: 10),
            "A placeholder row should render for the comment whose child_count exceeds its loaded descendants"
        )
        loadMoreRow.tap()

        // Success: the placeholder is replaced by the spliced-in subtree. The
        // first descendant's body text is a mechanism-independent proof the real
        // comments landed (not just that the placeholder went away).
        let splicedChild = app.cell(containing: "Morbi egestas tortor commodo mauris egestas varius")
        XCTAssertTrue(
            splicedChild.waitForExistence(timeout: 10),
            "The fetched subtree's first comment should appear after tapping load-more"
        )

        XCTAssertTrue(
            loadMoreRow.waitForNonExistence(timeout: 5),
            "The placeholder row should be gone once its subtree has loaded"
        )
    }
}
