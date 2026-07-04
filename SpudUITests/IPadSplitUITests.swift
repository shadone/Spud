//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import UIKit
import XCTest

/// iPad-only UITest verifying that opening a community from the Discover screen
/// pushes a two-column `CommunityReadingSplitViewController` (regular-width gate)
/// with the "No posts selected" placeholder in the secondary column.
///
/// Skipped on iPhone: the same tap path produces a single-column
/// `CommunityOrLoadingViewController` push on compact width.
class IPadSplitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test; skipped on non-iPad devices")
        }

        app = SBTUITunneledApplication()
        let launchOptions: [String] = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            AppLaunchArgument.seedSignedOutDefaultAccount.rawValue,
        ]
        app.launchTunnel(withOptions: launchOptions) {
            self.app.monitorRequests(matching: SBTRequestMatch(url: ".*"))

            // Catch-all 500 for any endpoint we don't explicitly stub.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*"),
                response: SBTStubResponse(response: "", returnCode: 500)
            )

            // Stub the community info fetch triggered when CommunityOrLoadingViewController
            // loads. The wildcard URL matches any host's /api/v3/community endpoint.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: ".*/api/v3/community",
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "community-tincidunt.json")
            )

            // --- Community-feed CONTENT stubs (test_discoverCommunity_tapPost_fillsDetailColumn) ---
            //
            // These let the reading split's PRIMARY column render a community feed and the
            // SECONDARY column fill with a post detail when a post is tapped. They are
            // registered AFTER the catch-all 500 above so they win (SBT evaluates stubs in
            // reverse registration order — later registration takes precedence).
            //
            // pictrs image stub so post thumbnails / avatars don't fall through to the 500
            // catch-all (which would spam the log and slow image loads). Returns a static
            // bundled "tv-pattern" image via the app's custom image content type.
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

            // The community feed itself. The reading-split feed issues getPosts filtered by
            // COMMUNITY — the actual request observed is
            //   GET /api/v3/post/list?sort=Hot&community_name=<name>@<instance>&show_nsfw=false
            // (see LemmyService.fetchFeed(.community), which builds it via
            // CommunityFilter.name(...)). It is distinguished from the FRONTPAGE feed, whose
            // request carries `type_=All` and NO `community_name` at all.
            //
            // The match is keyed only on the PRESENCE of a `community_name` param (the regex
            // `community_name=` matches any value) rather than a specific community. This is
            // deliberate: which Discover row the seeded directory surfaces first is NOT
            // deterministic — the bundled 4.9 MB seed populates the directory before any
            // network refresh, so the tapped row (and thus this feed's community_name) can be
            // e.g. technology@lemmy.ml rather than tincidunt. Whatever the row, the wildcard
            // `.*/api/v3/community` stub above resolves the OPENED community to tincidunt
            // (community id 9544), and this feed returns the same 2-post fixture; its first
            // post (id 1549703, "Nunc scelerisque...") is community 9544's post, so the
            // detail/comment stubs below (keyed on id 1549703) line up regardless of the row.
            //
            // The `community_name=` matcher also keeps this stub from shadowing the frontpage
            // feed, so the empty-split test's frontpage requests are unaffected.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: ".*/api/v3/post/list",
                    query: ["community_name="],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-list-all-hot.json")
            )

            // Post detail (getPost) for the first feed post, loaded into the secondary column
            // when the post is tapped. id=1549703 is the "Nunc scelerisque..." post.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: ".*/api/v3/post",
                    query: ["id=1549703"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-detail-1549703.json")
            )

            // Comment tree (getComments) for that post, fetched concurrently with the detail.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: ".*/api/v3/comment/list",
                    query: ["post_id=1549703"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "comment-list-1549703-Hot.json")
            )

            // The post creator's profile (getPersonDetails), in case the detail header resolves
            // the author lazily. Keeps it off the 500 catch-all.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: ".*/api/v3/user",
                    query: ["person_id=31989"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "user-31989.json")
            )

            // Stub the Lemmy Explorer (data.lemmyverse.net) multipart community
            // directory. With ResetFilesystem the DB is empty and the bundled seed
            // import is async — it may not complete within the 10-second cell wait.
            // Stubbing the network endpoints lets the ExplorerService refresh succeed
            // immediately so Discover cells appear before the timeout.
            //
            // Pattern order: specific before catch-all (SBT evaluates in reverse
            // registration order — later stubs win). The metadata endpoint returns
            // { "count": 1 } and the single part returns one community DTO.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*data\\.lemmyverse\\.net/data/community/0\\.json"),
                response: SBTStubResponse(fileNamed: "explorer-community-0.json")
            )
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*data\\.lemmyverse\\.net/data/community\\.json"),
                response: SBTStubResponse(fileNamed: "explorer-community-meta.json")
            )
        }
    }

    override func tearDownWithError() throws {
        let allRequestUrls = app.monitoredRequestsFlushAll().map { request in
            let httpMethod = request.request!.httpMethod!
            let url = request.request!.url!.absoluteString
            return " - \(httpMethod) \(url)"
        }
        .joined(separator: "\n")
        print("### Network requests intercepted during the test:\n\(allRequestUrls)")
    }

    /// Opening a community from Discover on iPad (regular width) pushes a two-column
    /// `CommunityReadingSplitViewController`. The secondary column shows "No posts selected"
    /// before any post is tapped.
    ///
    /// The test asserts that BOTH columns are simultaneously visible and that the primary
    /// column is geometrically LEFT of the secondary column, proving a two-column layout
    /// rather than a single-column push. Passing on a single-column layout is not possible
    /// because the "Back to Communities" back button only appears in the primary column's
    /// nav bar of the split, while "No posts selected" lives in the secondary column.
    func test_discoverCommunity_showsTwoColumnSplit() {
        // Navigate to the Communities tab (Posts | Communities | Search | Inbox | Account).
        // On iPad (iOS 18+) UITabBarController renders as a sidebar — `app.tabBars` finds
        // nothing because there is no UITabBar element. The sidebar tab items are exposed as
        // plain buttons in the accessibility hierarchy; `app.buttons["Communities"]` matches
        // both the traditional bottom tab-bar button (iPhone / compact) and the sidebar item
        // (iPad regular width).
        // On iOS 26 iPad the floating tab bar exposes each item as two nested button elements
        // (outer `_UIFloatingTabBarItemCell` + inner `_UIFloatingTabBarItemView` — both inherit
        // the "Communities" label). `.firstMatch` resolves the outermost one unambiguously.
        let communitiesTab = app.buttons["Communities"].firstMatch
        XCTAssertTrue(communitiesTab.waitForExistence(timeout: 10), "Communities tab button not found")
        communitiesTab.tap()

        // Tap the Discover communities entry point in the subscriptions view.
        // On this screen the entry renders as a `UICollectionViewCell` containing a
        // StaticText (not a Button). Tap the StaticText label directly — UICollectionView
        // forwards the tap to the cell's selection handler.
        let discoverEntry = app.staticTexts["Discover communities"].firstMatch
        XCTAssertTrue(discoverEntry.waitForExistence(timeout: 10), "Discover communities entry not found")
        discoverEntry.tap()

        // Wait for a directory community row to appear and tap it.
        //
        // `DiscoverCommunityRow` is a SwiftUI view with `.accessibilityAddTraits(.isButton)` —
        // it is exposed as a **button** (not a cell) in the XCUITest accessibility tree.
        // `app.cells` always returns empty here because there are no UITableViewCell /
        // UICollectionViewCell elements in the Discover screen.
        //
        // The accessibility label for every directory row ends with "N subscribers"
        // (e.g. "Technology, c/technology@lemmy.ml, 50K subscribers"), which is unique to
        // `DiscoverCommunityRow` — trend cards say "active this week" instead. This predicate
        // reliably picks the first directory entry without matching nav/tab buttons, so it
        // cannot accidentally tap a Communities tab button or a navigation title.
        //
        // The timeout is 20 s to accommodate the first-launch bundled seed import
        // (~4.9 MB .lzfse file seeded asynchronously by ExplorerService at startup).
        let firstCommunityRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS 'subscribers'"))
            .firstMatch
        XCTAssertTrue(
            firstCommunityRow.waitForExistence(timeout: 20),
            "No directory community rows appeared in Discover (expected buttons with 'subscribers' in label)"
        )
        firstCommunityRow.tap()

        // The secondary column of CommunityReadingSplitViewController shows the
        // "No posts selected" placeholder immediately, before any post is tapped.
        let placeholder = app.staticTexts["No posts selected"]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 10),
            "Expected 'No posts selected' placeholder in the secondary column of the reading split"
        )

        // Dual-column proof: the "Back to Communities" button is injected by
        // CommunityReadingSplitViewController.makeBackButton() onto the primary column's
        // navigation bar via UINavigationControllerDelegate. It only exists when the split
        // VC is on screen — a single-column CommunityOrLoadingViewController push does NOT
        // produce this button. Asserting BOTH elements are simultaneously present proves
        // that two columns are rendered at the same time.
        let backButton = app.buttons["Back to Communities"]
        XCTAssertTrue(
            backButton.exists,
            "Primary column back button 'Back to Communities' not found — expected both columns to be visible simultaneously"
        )

        // Horizontal layout proof: the primary column (left) must be geometrically left
        // of the secondary column placeholder (right). Both frames are in application
        // screen coordinates after the layout has settled (the placeholder
        // waitForExistence above ensures the split is on screen before frames are read).
        //
        // Comparison uses midX rather than minX: the placeholder label is constrained
        // to span the full width of the secondary column's view (leading → trailing), so
        // its minX is 0 in UIKit coordinates, whereas the back button is a narrow bar
        // item with minX ≈ 14. Using midX captures where each element is centred,
        // which is a reliable geometric discriminant for left-column vs right-column.
        let primaryMidX = backButton.frame.midX
        let secondaryMidX = placeholder.frame.midX
        XCTAssertLessThan(
            primaryMidX,
            secondaryMidX,
            "Primary column (midX \(primaryMidX)) should be left of secondary column (midX \(secondaryMidX))"
        )
    }

    /// The account's Activity area (`ActivitySummaryReadingSplitViewController`)
    /// renders as the same two-column reading split on iPad regular width — the
    /// timeline in the primary column, the Summary dashboard pinned in the secondary.
    ///
    /// **Skipped — auth-gated with no UITest seam.** The Activity row lives on the
    /// *signed-in* Account tab (`AccountViewController` swaps in
    /// `AccountSignedOutViewController` when the default account is signed out), so
    /// driving this screen needs a signed-in account in the app's database. The only
    /// account-seeding launch argument that exists is
    /// `AppLaunchArgument.seedSignedOutDefaultAccount` (a *signed-out* account, so the
    /// Account tab shows the signed-out screen — no Activity row). There is no
    /// signed-in seed, no login launch argument, and no SBTUITestTunnel login/JWT
    /// stub. Building one is explicitly out of scope for this task.
    ///
    /// The two-column layout is instead proven deterministically, without auth, by
    /// `SpudSnapshotTests/ActivityIPadSplitSnapshotTests` (in-memory DB, fixed
    /// `asOf`, `.iPadPro11(.landscape)`), which asserts the same side-by-side column
    /// geometry (timeline left, Summary right) that this UITest would have. The live
    /// tap path is covered by manual on-device verification.
    func test_accountActivity_showsTwoColumnSplit() throws {
        throw XCTSkip(
            "Activity is auth-gated (signed-in Account tab) with no signed-in-account UITest seam; " +
                "covered by ActivityIPadSplitSnapshotTests + manual on-device verify"
        )
    }

    /// Opening a community from Discover on iPad (regular width) and then tapping a post
    /// fills the SECONDARY (detail) column of `CommunityReadingSplitViewController`.
    ///
    /// This is the CONTENT companion to `test_discoverCommunity_showsTwoColumnSplit`, which
    /// only proves the EMPTY split (the "No posts selected" placeholder). Here we prove the
    /// full reading flow:
    ///   1. the PRIMARY column's community feed renders posts,
    ///   2. tapping a post REPLACES the placeholder with that post's detail in the SECONDARY
    ///      column (the placeholder disappears),
    ///   3. the detail header lands in the RIGHT/secondary column (geometric proof), not a
    ///      single-column push.
    ///
    /// Determinism: the wildcard `.*/api/v3/community` stub (registered in setUp) resolves
    /// EVERY tapped Discover row's getCommunity call to tincidunt (community id 9544), so the
    /// persisted community — and thus the post-detail (id 1549703) and comment-tree stubs — always
    /// line up. The community feed's getPosts request itself carries the TAPPED row's
    /// `community_name` (non-deterministic, e.g. technology@lemmy.ml — the bundled seed picks the
    /// first row, NOT tincidunt), but the `community_name=` wildcard stub in setUp matches any
    /// value, so whichever community is opened, its feed returns the same 2-post fixture. All
    /// three content stubs (feed, detail, comments) are wired in setUp.
    func test_discoverCommunity_tapPost_fillsDetailColumn() {
        // --- Navigate to the reading split (same path as the empty-split test). ---
        // See test_discoverCommunity_showsTwoColumnSplit for why each selector is shaped the
        // way it is (sidebar tab buttons, the Discover StaticText cell, the "subscribers"
        // directory-row predicate, and the first-launch seed timeout).
        let communitiesTab = app.buttons["Communities"].firstMatch
        XCTAssertTrue(communitiesTab.waitForExistence(timeout: 10), "Communities tab button not found")
        communitiesTab.tap()

        let discoverEntry = app.staticTexts["Discover communities"].firstMatch
        XCTAssertTrue(discoverEntry.waitForExistence(timeout: 10), "Discover communities entry not found")
        discoverEntry.tap()

        let firstCommunityRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS 'subscribers'"))
            .firstMatch
        XCTAssertTrue(
            firstCommunityRow.waitForExistence(timeout: 20),
            "No directory community rows appeared in Discover (expected buttons with 'subscribers' in label)"
        )
        firstCommunityRow.tap()

        // --- (1) PRIMARY column renders the community feed. ---
        // The placeholder is still present at this point (nothing tapped yet); its existence
        // confirms we are in the two-column reading split, not a single-column push.
        let placeholder = app.staticTexts["No posts selected"]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 10),
            "Expected the empty-split 'No posts selected' placeholder before tapping a post"
        )

        // The first post cell must appear in the PRIMARY column's feed. This is the RED point
        // until the community-feed getPosts stub (community_name=tincidunt) is wired: without
        // it the feed hits the catch-all 500 and stays empty. `app.cell(containing:)` matches a
        // table cell whose accessibility label contains the post title.
        let firstPostCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(
            firstPostCell.waitForExistence(timeout: 10),
            "Primary column community feed did not render the first post cell"
        )

        // Record the feed's horizontal centre BEFORE tapping, to prove later that the detail
        // lands to its RIGHT. (After the tap the detail may scroll the feed selection, but the
        // primary column's frame stays put.)
        let primaryFeedMidX = firstPostCell.frame.midX

        // --- (2) Tapping the post fills the SECONDARY (detail) column. ---
        firstPostCell.tap()

        // The detail header (id "postDetailHeader") appears with the post's title. On the
        // reading split this is hosted in the SECONDARY column, replacing the placeholder.
        let detailHeaderCell = app.cells["postDetailHeader"]
        XCTAssertTrue(
            detailHeaderCell.waitForExistence(timeout: 10),
            "Tapping the post should fill the secondary column with the post detail header"
        )
        let detailTitle = detailHeaderCell.staticTexts["title"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5), "Detail header should show the post title")
        XCTAssertTrue(
            detailTitle.label.contains("Nunc scelerisque tortor eget ligula pretium tempor"),
            "Detail title should be the tapped post's title, got: \(detailTitle.label)"
        )

        // The placeholder must be GONE — the secondary column's content view was swapped from
        // the "No posts selected" placeholder to the post detail.
        XCTAssertTrue(
            placeholder.waitForNonExistence(timeout: 5),
            "'No posts selected' placeholder should disappear once a post fills the detail column"
        )

        // --- (3) Geometric proof: the detail header sits in the RIGHT/secondary column. ---
        // Mirrors the empty-split test's midX technique: if the post had pushed onto a single
        // column instead of filling the split's detail, the detail header would occupy roughly
        // the same x-band as the feed (or replace it), not sit to its right. The secondary
        // column is laid out to the right of the primary, so the header's midX must exceed the
        // primary feed cell's midX.
        let detailMidX = detailHeaderCell.frame.midX
        XCTAssertGreaterThan(
            detailMidX,
            primaryFeedMidX,
            "Detail header (midX \(detailMidX)) should be right of the primary feed (midX \(primaryFeedMidX)), proving it filled the secondary column"
        )
    }
}
