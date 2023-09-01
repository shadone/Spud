//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import XCTest

class SpudUITests: XCTestCase {
    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        app = SBTUITunneledApplication()
        let launchOptions = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            AppLaunchArgument.deleteCoreDataStorage.rawValue,
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
                    query: ["&type_=All", "&sort=Hot", "&page=1"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-list-all-hot.json")
            )

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/post",
                    query: ["&id=1549703"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-detail-1549703.json")
            )

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/comment/list",
                    query: ["&post_id=1549703", "&max_depth=8", "&sort=Hot"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "comment-list-1549703-Hot.json")
            )

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/user",
                    query: ["&person_id=31989"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "user-31989.json")
            )
        }
    }

    override func tearDownWithError() throws {
        let allRequestUrls = app.monitoredRequestsFlushAll().map { request in
            let httpMethod = request.request!.httpMethod!
            let url = request.request!.url!.absoluteString
            let requestTime = request.requestTime
            return " - \(httpMethod) \(url) [\(requestTime)ms]"
        }
        .joined(separator: "\n")

        print("### Network requests intercepted during the test:\n\(allRequestUrls)")
    }

    func testExample() throws {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        let firstCellSubtitle = firstCell.staticTexts["subtitle"].label
        XCTAssertTrue(firstCellSubtitle.contains("tincidunt"))

        let secondCell = app.cell(containing: "Quisque eget tortor eu enim scelerisque aliquam")
        let secondCellSubtitle = secondCell.staticTexts["subtitle"].label
        XCTAssertTrue(secondCellSubtitle.contains("consequat"))
    }

    func testPostDetail() throws {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        firstCell.tap()

        let detailHeaderCell = app.cells["postDetailHeader"]

        let title = detailHeaderCell.staticTexts["title"].label
        XCTAssertTrue(title.contains("Nunc scelerisque tortor eget ligula pretium tempor"))

        let attribution = detailHeaderCell.buttons["attribution"].label
        XCTAssertTrue(attribution.contains("in tincidunt by finibus"))

        let firstComment = app.cell(containing: "Nunc sagittis nulla tempor, luctus lectus a, molestie nisl")
        XCTAssertTrue(firstComment.exists)
    }

    func test_PostDetail_TapOnPostCreator() throws {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        firstCell.tap()

        let detailHeaderCell = app.cells["postDetailHeader"]

        let attribution = detailHeaderCell.buttons["attribution"]
        XCTAssertTrue(attribution.label.contains("in tincidunt by finibus"))

        attribution.coordinate(withNormalizedOffset: .zero)
            .withOffset(.init(dx: 100, dy: 10))
            .tap()

        // expect the loading screen
        XCTAssertTrue(app.staticTexts["loading"].exists)

        // let the loading screen to disappear
        XCTAssertTrue(app.staticTexts["Nunc Finibus Augue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["finibus"].exists)

        let collectionViewsQuery = app.collectionViews
        XCTAssertTrue(collectionViewsQuery.staticTexts["2.1K"].exists)
        XCTAssertTrue(collectionViewsQuery.staticTexts["16.3K"].exists)
        XCTAssertTrue(collectionViewsQuery.staticTexts["3mo"].exists)
        XCTAssertTrue(collectionViewsQuery.buttons["Posts, 86"].exists)
        XCTAssertTrue(collectionViewsQuery.buttons["Comments, 203"].exists)
    }
}
