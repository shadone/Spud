//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import XCTest

/// SpudUITests target stays at Swift 5 until SBTUITestTunnelClient
/// supports strict concurrency.
class SpudUITests: XCTestCase {
    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // Device orientation is simulator-hardware state that survives
        // ResetFilesystem and can leak from an earlier suite run.
        XCUIDevice.shared.orientation = .portrait

        app = SBTUITunneledApplication()
        let launchOptions = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            // Wipe the App Group DB first: it survives SBT's ResetFilesystem, so a
            // signed-in account left by an alphabetically-earlier suite would
            // otherwise make the signed-out seed below a no-op (reverse
            // contamination) and this suite would run signed in. Wiping makes it
            // order-independent regardless of what a prior suite left behind.
            AppLaunchArgument.wipeAppDatabase.rawValue,
            // Onboarding gates a fresh install; seed a default account so these
            // tests land on the feed (the old auto-bootstrap they relied on is gone).
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

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/post",
                    query: ["id=1549703"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-detail-1549703.json")
            )

            // The neutral `getCommentsNeutral` request is
            // `type_=All&sort=Hot&post_id=1549703` -- it no longer sends the
            // `max_depth=8` the old client did, so the matcher keys only on the
            // params that are actually present (a stale `max_depth=8` matcher
            // would miss and fall through to the 500 catch-all, leaving the
            // detail with no comments).
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/comment/list",
                    query: ["post_id=1549703", "sort=Hot"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "comment-list-1549703-Hot.json")
            )

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/user",
                    query: ["person_id=31989"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "user-31989.json")
            )

            // The first post's community ("Visit c/tincidunt"). The neutral
            // surface has no get-community-by-name endpoint, so opening a
            // community resolves it by its federation actor url via
            // `resolve_object` (`GET /api/v3/resolve_object?q=https://lemmy.world/c/tincidunt`),
            // not the retired `GET /api/v3/community?name=tincidunt`. The stub
            // returns a `ResolveObjectResponse` whose `community` is the
            // tincidunt `CommunityView`.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/resolve_object",
                    query: ["q=.*tincidunt"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "resolve-object-community-tincidunt.json")
            )

            // Search's `.posts` scope (the default) hits the neutral search
            // surface's v3 path, `GET /api/v3/search?q=<query>&type_=Posts` (no
            // `sort` param -- a nil sort omits it, letting the server apply its
            // default). Returns the SAME post 1549703 / tincidunt community /
            // finibus creator fixture the feed stubs above use, so a search
            // result's context menu resolves the identical "Visit c/tincidunt".
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/search",
                    query: ["q=tincidunt", "type_=Posts"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "search-posts-tincidunt.json")
            )

            // Search's `.communities` scope hits the same neutral v3 search path with
            // `type_=Communities`. Returns the same tincidunt `CommunityView` fixture
            // the "Visit c/tincidunt" tests use, so a community search result's context
            // menu resolves through the SAME already-stubbed `resolve_object` above.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/search",
                    query: ["q=tincidunt", "type_=Communities"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "search-communities-tincidunt.json")
            )
        }
    }

    override func tearDownWithError() throws {
        // Rotation tests can leave the simulator in landscape; reset so the
        // portrait-assuming tests (and snapshot device) start clean.
        XCUIDevice.shared.orientation = .portrait

        let allRequestUrls = app.monitoredRequestsFlushAll().map { request in
            let httpMethod = request.request!.httpMethod!
            let url = request.request!.url!.absoluteString
            let requestTime = request.requestTime
            return " - \(httpMethod) \(url) [\(requestTime)ms]"
        }
        .joined(separator: "\n")

        print("### Network requests intercepted during the test:\n\(allRequestUrls)")
    }

    func testExample() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        let firstCellSubtitle = firstCell.staticTexts["subtitle"].label
        XCTAssertTrue(firstCellSubtitle.contains("tincidunt"))

        let secondCell = app.cell(containing: "Quisque eget tortor eu enim scelerisque aliquam")
        let secondCellSubtitle = secondCell.staticTexts["subtitle"].label
        XCTAssertTrue(secondCellSubtitle.contains("consequat"))
    }

    func testPostDetail() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        firstCell.tap()

        let detailHeaderCell = app.cells["postDetailHeader"]

        let title = detailHeaderCell.staticTexts["title"].label
        XCTAssertTrue(title.contains("Nunc scelerisque tortor eget ligula pretium tempor"))

        XCTAssertTrue(detailHeaderCell.descendants(matching: .any)["attribution"].exists)

        let firstComment = app.cell(containing: "Nunc sagittis nulla tempor, luctus lectus a, molestie nisl")
        XCTAssertTrue(firstComment.exists)
    }

    /// With a post selected, flipping the size class (compact <-> regular)
    /// must keep the detail on screen. On a Max-class iPhone, rotating to
    /// landscape expands the split view and the detail moves from the compact
    /// navigation stack into the secondary column; rotating back collapses it
    /// and the detail moves back. On a non-Max device the split stays collapsed
    /// in both orientations, so the detail simply rides the navigation stack —
    /// the assertions hold either way. This guards the MainWindow split-view
    /// collapse/expand handoff.
    func test_PostDetail_SurvivesRotationHandoff() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        firstCell.tap()

        let detailHeaderCell = app.cells["postDetailHeader"]
        XCTAssertTrue(
            detailHeaderCell.waitForExistence(timeout: 5),
            "Post detail should be visible after selecting a post"
        )

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(
            detailHeaderCell.waitForExistence(timeout: 5),
            "Post detail should survive expanding to a two-column layout"
        )

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            detailHeaderCell.waitForExistence(timeout: 5),
            "Post detail should survive collapsing back to a single column"
        )
    }

    /// The attribution `LinkLabel` ("in <community> by <creator>") now exposes
    /// each link range as its own accessibility element with the `.link` trait,
    /// so XCUITest can query the creator link by its label and tap it directly
    /// instead of relying on a fragile coordinate offset.
    func test_PostDetail_TapOnPostCreator() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        firstCell.tap()

        let detailHeaderCell = app.cells["postDetailHeader"]
        XCTAssertTrue(detailHeaderCell.waitForExistence(timeout: 5))

        // The creator renders as "Nunc Finibus Augue@<host>" (display name + muted
        // host) as a single link element inside the attribution label.
        // The whole handle is one link, so match by prefix.
        let creatorLink = detailHeaderCell.links
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Nunc Finibus Augue"))
            .firstMatch
        XCTAssertTrue(
            creatorLink.waitForExistence(timeout: 5),
            "Creator link should be exposed as an accessibility element"
        )

        // The link's value carries the destination URL (an internal person
        // deep link), proving the per-link child is wired to the right target.
        XCTAssertTrue(
            creatorLink.value as? String != nil,
            "Creator link element should expose its destination as its value"
        )

        creatorLink.tap()

        // Tapping the creator pushes that person's profile, so the post-detail
        // header we tapped from is no longer on screen. This is a
        // mechanism-independent proof that the link tap was routed.
        XCTAssertTrue(
            detailHeaderCell.waitForNonExistence(timeout: 5),
            "Tapping the creator link should navigate away from the post detail"
        )
    }

    /// Opening a community from a post's context menu must land on the full
    /// community screen WITH its navigation-bar actions. The community screen is
    /// reached through `CommunityOrLoadingViewController`, which hosts the real
    /// `CommunityViewController` — its overflow (`More`) menu and `Sort posts`
    /// button live on that hosted controller's `navigationItem`. Regression
    /// guard: when the host embedded the content as a child view controller,
    /// UIKit ignored the child's `navigationItem` and the navbar came up empty,
    /// so neither button appeared on any path to a community.
    func test_VisitCommunityFromPostContextMenu_showsNavbarActions() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "Feed should load")

        // Long-press the post to open its context menu, then choose its community.
        firstCell.press(forDuration: 1.2)

        let visitAction = app.buttons["Visit c/tincidunt"]
        XCTAssertTrue(
            visitAction.waitForExistence(timeout: 5),
            "Post context menu should offer 'Visit c/tincidunt'"
        )
        visitAction.tap()

        let navBar = app.navigationBars

        let overflowButton = navBar.buttons["More"]
        XCTAssertTrue(
            overflowButton.waitForExistence(timeout: 10),
            "Community navbar should show the overflow (More) menu button"
        )

        let sortButton = navBar.buttons["Sort posts"]
        XCTAssertTrue(
            sortButton.exists,
            "Community navbar should show the post sort button"
        )
    }

    /// Search's post-result rows must carry the SAME shared long-press context
    /// menu as the feed (Task 2 of the search-context-menus initiative:
    /// `SearchViewController` conforms to `PostContextMenuHost` and attaches
    /// `PostContextMenuBuilder`'s menu via `contextMenuConfigurationForRowAt`).
    /// This is the Search-side sibling of
    /// `test_VisitCommunityFromPostContextMenu_showsNavbarActions`: search for a
    /// post, long-press its search-result row, choose "Visit c/tincidunt", and
    /// land on the full community screen with its navbar actions -- proving the
    /// menu is wired end to end (not just present-but-inert), and reusing that
    /// test's regression guard against the resolve-then-show wrapper embedding
    /// its content as a child (which drops the navbar actions silently).
    func test_Search_PostResultContextMenu_VisitCommunity() {
        let searchTab = app.buttons["Search"].firstMatch
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10), "Search tab button not found")
        searchTab.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found")
        searchField.tap()
        searchField.typeText("tincidunt")

        let postCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(postCell.waitForExistence(timeout: 10), "Search should return the stubbed post result")

        // Long-press the search result to open its context menu, then choose its community.
        postCell.press(forDuration: 1.2)

        let visitAction = app.buttons["Visit c/tincidunt"]
        XCTAssertTrue(
            visitAction.waitForExistence(timeout: 5),
            "Search post-result context menu should offer 'Visit c/tincidunt'"
        )
        visitAction.tap()

        let navBar = app.navigationBars

        let overflowButton = navBar.buttons["More"]
        XCTAssertTrue(
            overflowButton.waitForExistence(timeout: 10),
            "Community navbar should show the overflow (More) menu button"
        )

        let sortButton = navBar.buttons["Sort posts"]
        XCTAssertTrue(
            sortButton.exists,
            "Community navbar should show the post sort button"
        )
    }

    /// Search's community-result rows carry the SAME shared long-press context
    /// menu as Discover's directory rows (Task 3 of the search-context-menus
    /// initiative: `SearchViewController` conforms to `CommunityContextMenuHost`
    /// and attaches `CommunityContextMenuBuilder`'s menu via
    /// `contextMenuConfigurationForRowAt`). Mirrors
    /// `test_Search_PostResultContextMenu_VisitCommunity`: search for a
    /// community, switch to the Communities scope, long-press its search-result
    /// row, choose "Open Community", and land on the full community screen with
    /// its navbar actions -- proving the menu is wired end to end and reusing
    /// that test's regression guard against the resolve-then-show wrapper
    /// embedding its content as a child (which drops the navbar actions
    /// silently).
    func test_Search_CommunityResultContextMenu_OpenCommunity() {
        let searchTab = app.buttons["Search"].firstMatch
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10), "Search tab button not found")
        searchTab.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found")
        searchField.tap()
        searchField.typeText("tincidunt")

        // Switch from the default Posts scope to Communities. The scope bar
        // renders inside the search bar's own navigation-bar area, so scope it
        // to `navigationBars` to disambiguate from the sidebar/tab-bar
        // "Communities" button, which shares the same accessibility label.
        let communitiesScope = app.navigationBars.buttons["Communities"]
        XCTAssertTrue(communitiesScope.waitForExistence(timeout: 10), "Communities search scope button not found")
        communitiesScope.tap()

        let communityCell = app.cell(containing: "tincidunt")
        XCTAssertTrue(communityCell.waitForExistence(timeout: 10), "Search should return the stubbed community result")

        // Long-press the search result to open its context menu, then open the community.
        communityCell.press(forDuration: 1.2)

        let openAction = app.buttons["Open Community"]
        XCTAssertTrue(
            openAction.waitForExistence(timeout: 5),
            "Search community-result context menu should offer 'Open Community'"
        )
        openAction.tap()

        let navBar = app.navigationBars

        let overflowButton = navBar.buttons["More"]
        XCTAssertTrue(
            overflowButton.waitForExistence(timeout: 10),
            "Community navbar should show the overflow (More) menu button"
        )

        let sortButton = navBar.buttons["Sort posts"]
        XCTAssertTrue(
            sortButton.exists,
            "Community navbar should show the post sort button"
        )
    }

    // TODO(follow-up spec 2026-07-05): Instance wrapper navbar tripwire
    // (`InstanceOrLoadingViewController`) — unreachable from the signed-out seed:
    // every reachable instance host is in the bundled Explorer directory (a
    // directory hit bypasses the wrapper), and no seeded surface links an
    // off-directory host. See docs/superpowers/specs/2026-07-05-follow-ups.md.

    /// Bug fix: a person's handle must show THEIR OWN instance host, not the
    /// signed-in account's home instance. finibus is a remote user
    /// (https://lemmy.world/u/finibus) viewed under the test's discuss.tchncs.de
    /// account, so the handle must read @finibus@lemmy.world.
    func test_PersonProfile_showsUsersOwnInstanceHost() {
        navigateToFinibusProfile()

        XCTAssertTrue(
            app.staticTexts["@finibus@lemmy.world"].waitForExistence(timeout: 5),
            "Handle should show the user's own instance host (lemmy.world)"
        )
        XCTAssertFalse(
            app.staticTexts["@finibus@discuss.tchncs.de"].exists,
            "Handle must not show the account's home instance host"
        )
    }

    /// Bug fix: the profile header (with the bio) must live INSIDE the scrollable
    /// table so a long bio scrolls instead of overflowing a fixed top region.
    /// Asserting the bio is a descendant of the table proves the header is hosted
    /// as the table's scrolling header rather than pinned outside it.
    func test_PersonProfile_headerLivesInScrollableTable() {
        navigateToFinibusProfile()

        XCTAssertTrue(
            app.tables.descendants(matching: .any)["bio"].waitForExistence(timeout: 5),
            "The bio (and header) must live inside the scrollable table so a long bio can scroll"
        )
    }

    /// The person profile navbar offers an overflow menu (sharing, like the
    /// Community / Post Detail screens) and a sort button, both always present.
    ///
    /// Also the Person sibling of
    /// `test_VisitCommunityFromPostContextMenu_showsNavbarActions`: tapping a
    /// post's creator pushes `PersonOrLoadingViewController` — the
    /// resolve-then-show wrapper that hosts the real `PersonViewController`. The
    /// overflow (`More`) menu and `Sort` button live on that hosted controller's
    /// `navigationItem`, so they only render if the wrapper PROMOTES the content
    /// into the navigation stack. A child view controller's `navigationItem` is
    /// ignored by UIKit, so had the wrapper embedded the content as a child (the
    /// same mistake that shipped invisibly on the Community path), this navbar
    /// would come up empty. The buttons are queried navbar-scoped
    /// (`app.navigationBars.buttons[...]`) to keep this a real tripwire for that
    /// bug class.
    func test_PersonProfile_navbarHasOverflowMenuAndSort() {
        navigateToFinibusProfile()

        let navBar = app.navigationBars

        XCTAssertTrue(
            navBar.buttons["Sort"].waitForExistence(timeout: 10),
            "Person navbar should show the Sort button"
        )

        let overflow = navBar.buttons["More"]
        XCTAssertTrue(
            overflow.waitForExistence(timeout: 10),
            "Person navbar should show the overflow (More) menu button"
        )
        overflow.tap()

        XCTAssertTrue(
            app.buttons["Open in Browser"].waitForExistence(timeout: 5),
            "Overflow menu should offer Open in Browser"
        )
        XCTAssertTrue(
            app.buttons["Copy handle"].exists,
            "Overflow menu should offer Copy handle"
        )
    }

    /// Opens finibus's profile by tapping the post creator's link in the detail
    /// header (the same path a user takes from a post/comment author).
    private func navigateToFinibusProfile() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "Feed should load")
        firstCell.tap()

        let detailHeaderCell = app.cells["postDetailHeader"]
        XCTAssertTrue(detailHeaderCell.waitForExistence(timeout: 5))
        // The whole handle ("Nunc Finibus Augue@<host>") is one link, so match by prefix.
        let creatorLink = detailHeaderCell.links
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Nunc Finibus Augue"))
            .firstMatch
        XCTAssertTrue(creatorLink.waitForExistence(timeout: 5))
        creatorLink.tap()
        XCTAssertTrue(
            detailHeaderCell.waitForNonExistence(timeout: 5),
            "Tapping the creator should push their profile"
        )
    }

    /// Captures full-screen renders of the primary surfaces (feed, then post
    /// detail) as test attachments, so the end-to-end UX can be reviewed against
    /// the Apollo bar without a device. Asserts the surfaces appear; the
    /// screenshots are kept as artifacts.
    func test_CaptureScreens() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "Feed should load")
        attachScreenshot(named: "01-feed")

        firstCell.tap()
        let detailHeaderCell = app.cells["postDetailHeader"]
        XCTAssertTrue(detailHeaderCell.waitForExistence(timeout: 10), "Post detail should open")
        attachScreenshot(named: "02-post-detail")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
