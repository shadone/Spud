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
        let firstCell = app.cell(containing: "Fuck SUVs in particular")
        let firstCellSubtitle = firstCell.staticTexts["subtitle"].label
        XCTAssertTrue(firstCellSubtitle.contains("fuckcars"))

        let secondCell = app.cell(containing: "Glad to see Lemmy users appreciating diversity")
        let secondCellSubtitle = secondCell.staticTexts["subtitle"].label
        XCTAssertTrue(secondCellSubtitle.contains("lemmyshitpost"))
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
