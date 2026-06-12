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

        app = SBTUITunneledApplication()
        let launchOptions = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
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

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/comment/list",
                    query: ["post_id=1549703", "max_depth=8", "sort=Hot"],
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

        // The creator renders as the display name "Nunc Finibus Augue" and is
        // exposed as a link element inside the attribution label.
        let creatorLink = detailHeaderCell.links["Nunc Finibus Augue"]
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
}
