//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
import UIKit
@testable import Spud

/// A fake `CommunityContextMenuHost` driving the builder in isolation, recording
/// every call instead of dispatching through `LemmyService` / `AppDatabase`.
@MainActor
final class FakeCommunityContextMenuHost: UIViewController, CommunityContextMenuHost {
    private(set) var openedResults: [SearchCommunityResult] = []
    private(set) var subscribedCalls: [(result: SearchCommunityResult, subscribed: Bool)] = []
    private(set) var mutedCalls: [(result: SearchCommunityResult, duration: MuteDuration)] = []
    private(set) var unmutedResults: [SearchCommunityResult] = []
    private(set) var blockedResults: [SearchCommunityResult] = []
    var isMuted = false

    func communityOpen(_ result: SearchCommunityResult) {
        openedResults.append(result)
    }

    func communitySetSubscribed(_ result: SearchCommunityResult, subscribed: Bool) {
        subscribedCalls.append((result, subscribed))
    }

    func communityIsMuted(_: SearchCommunityResult) -> Bool {
        isMuted
    }

    func communityMute(_ result: SearchCommunityResult, duration: MuteDuration) {
        mutedCalls.append((result, duration))
    }

    func communityUnmute(_ result: SearchCommunityResult) {
        unmutedResults.append(result)
    }

    func communityBlock(_ result: SearchCommunityResult) {
        blockedResults.append(result)
    }
}

/// Minimal `SearchCommunityResult` test factory.
extension SearchCommunityResult {
    static func fixture(
        serverCommunityId: Lemmy.CommunityID = 1,
        name: String = "tincidunt",
        followState: FollowState = .notFollowing,
        isNsfw: Bool = false,
        communityUrl: String = "https://lemmy.world/c/tincidunt",
        isBlocked: Bool = false
    ) -> SearchCommunityResult {
        SearchCommunityResult(
            serverCommunityId: serverCommunityId,
            name: name,
            qualifiedName: "!\(name)@lemmy.world",
            instance: InstanceActorId(from: "lemmy.world")!,
            subscribersText: "100",
            iconUrl: nil,
            followState: followState,
            isNsfw: isNsfw,
            communityUrl: communityUrl,
            isBlocked: isBlocked
        )
    }
}

@MainActor
struct CommunityContextMenuBuilderTests {
    /// Flattens a menu into the ordered titles of its actions and nested menus.
    private func allTitles(_ menu: UIMenu) -> [String] {
        menu.children.flatMap { element -> [String] in
            switch element {
            case let action as UIAction: [action.title]
            case let submenu as UIMenu: [submenu.title] + allTitles(submenu)
            default: []
            }
        }
    }

    private func hasDestructive(_ menu: UIMenu, title: String) -> Bool {
        menu.children.contains { element in
            if let submenu = element as? UIMenu {
                return submenu.children.contains {
                    ($0 as? UIAction).map { $0.title == title && $0.attributes.contains(.destructive) } ?? false
                }
            }
            if let action = element as? UIAction {
                return action.title == title && action.attributes.contains(.destructive)
            }
            return false
        }
    }

    private func performAction(titled title: String, in menu: UIMenu) {
        for element in menu.children {
            if let action = element as? UIAction, action.title == title {
                action.performWithSender(nil, target: nil)
                return
            }
            if let submenu = element as? UIMenu {
                performAction(titled: title, in: submenu)
            }
        }
    }

    @Test
    func includesCoreActionsWhenNotSubscribedNotMuted() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .notFollowing)
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Open Community"))
        #expect(titles.contains("Subscribe"))
        #expect(!titles.contains("Unsubscribe"))
        #expect(titles.contains("Mute"))
        #expect(!titles.contains("Unmute"))
        #expect(titles.contains("Share"))
        #expect(titles.contains("Copy Link"))
        #expect(hasDestructive(menu, title: "Block Community"))
    }

    @Test
    func showsUnsubscribeWhenSubscribed() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .accepted)
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Unsubscribe"))
        #expect(!titles.contains("Subscribe"))
    }

    @Test
    func showsUnmuteWhenMuted() {
        let host = FakeCommunityContextMenuHost()
        host.isMuted = true
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Unmute"))
        #expect(!titles.contains("Mute"))
    }

    @Test
    func openCommunityInvokesHostOpen() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Open Community", in: menu)
        #expect(host.openedResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func subscribeInvokesHostSetSubscribed() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .notFollowing)
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Subscribe", in: menu)
        #expect(host.subscribedCalls.count == 1)
        #expect(host.subscribedCalls.first?.subscribed == true)
    }

    @Test
    func unsubscribeInvokesHostSetSubscribed() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .accepted)
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Unsubscribe", in: menu)
        #expect(host.subscribedCalls.count == 1)
        #expect(host.subscribedCalls.first?.subscribed == false)
    }

    @Test
    func unmuteInvokesHostUnmute() {
        let host = FakeCommunityContextMenuHost()
        host.isMuted = true
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Unmute", in: menu)
        #expect(host.unmutedResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func blockInvokesHostBlock() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Block Community", in: menu)
        #expect(host.blockedResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }
}
