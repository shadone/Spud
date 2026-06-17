//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUtilKit
import XCTest
@testable import Spud

@MainActor
final class AppNavigationRoutingTests: XCTestCase {
    private final class SpyNavigator: AppNavigating {
        var calls: [String] = []
        func selectFeed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?) {
            calls.append("feed:\(listing):\(String(describing: sort))")
        }

        func selectSearch(query: String) {
            calls.append("search:\(query)")
        }

        func presentNewPost() {
            calls.append("newPost")
        }

        func selectInbox() {
            calls.append("inbox")
        }

        func display(communityName: String, instance _: InstanceActorId, accountKeychainId _: String) {
            calls.append("community:\(communityName)")
        }
    }

    func test_navigate_withActiveWindow_routesImmediately() {
        let coordinator = AppCoordinator.shared
        let spy = SpyNavigator()
        coordinator.setActiveWindow(spy)

        coordinator.navigate(.inbox)
        coordinator.navigate(.search(query: "cats"))

        XCTAssertEqual(spy.calls, ["inbox", "search:cats"])
        XCTAssertNil(coordinator.pendingNavigation)

        coordinator.setActiveWindow(nil)
    }

    func test_navigate_withNoWindow_storesPending_thenReplaysOnRegister() {
        let coordinator = AppCoordinator.shared
        coordinator.setActiveWindow(nil)

        coordinator.navigate(.newPost)
        XCTAssertEqual(coordinator.pendingNavigation, .newPost)

        let spy = SpyNavigator()
        coordinator.setActiveWindow(spy) // registering a window drains pending

        XCTAssertEqual(spy.calls, ["newPost"])
        XCTAssertNil(coordinator.pendingNavigation)

        coordinator.setActiveWindow(nil)
    }
}
