//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUtilKit
import Testing
@testable import Spud

@MainActor
struct AppNavigationRoutingTests {
    private final class SpyNavigator: AppNavigating {
        var calls: [String] = []
        func selectFeed(listing: Lemmy.ListingType, sort: Lemmy.SortType?) {
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

        func selectSavedFeed(sort: Lemmy.SortType?) {
            calls.append("savedFeed:\(String(describing: sort))")
        }
    }

    @Test
    func navigate_withActiveWindow_routesImmediately() {
        let coordinator = AppCoordinator.shared
        let spy = SpyNavigator()
        coordinator.setActiveWindow(spy)

        coordinator.navigate(.inbox)
        coordinator.navigate(.search(query: "cats"))

        #expect(spy.calls == ["inbox", "search:cats"])
        #expect(coordinator.pendingNavigation == nil)

        coordinator.setActiveWindow(nil)
    }

    @Test
    func navigate_savedFeed_routesToSavedFeed() {
        let coordinator = AppCoordinator.shared
        let spy = SpyNavigator()
        coordinator.setActiveWindow(spy)

        coordinator.navigate(.savedFeed(sort: nil))

        #expect(spy.calls == ["savedFeed:nil"])
        coordinator.setActiveWindow(nil)
    }

    @Test
    func navigate_withNoWindow_storesPending_thenReplaysOnRegister() {
        let coordinator = AppCoordinator.shared
        coordinator.setActiveWindow(nil)

        coordinator.navigate(.newPost)
        #expect(coordinator.pendingNavigation == .newPost)

        let spy = SpyNavigator()
        coordinator.setActiveWindow(spy) // registering a window drains pending

        #expect(spy.calls == ["newPost"])
        #expect(coordinator.pendingNavigation == nil)

        coordinator.setActiveWindow(nil)
    }
}
