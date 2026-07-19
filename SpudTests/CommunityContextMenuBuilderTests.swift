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
    private(set) var sharedResults: [SearchCommunityResult] = []
    private(set) var copiedLinkResults: [SearchCommunityResult] = []
    private(set) var blockedResults: [SearchCommunityResult] = []
    private(set) var toggleNotifyResults: [SearchCommunityResult] = []
    private(set) var toggleFavoriteResults: [SearchCommunityResult] = []
    var isMuted = false
    var isNotifying = false
    /// `nil` by default (inherits the protocol-extension default), matching a
    /// host that doesn't offer Favourite at all (e.g. Search). Set to `false`
    /// or `true` to opt in and drive the Favourite action's state.
    var favoriteState: Bool?

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

    func communityShare(_ result: SearchCommunityResult) {
        sharedResults.append(result)
    }

    func communityCopyLink(_ result: SearchCommunityResult) {
        copiedLinkResults.append(result)
    }

    func communityBlock(_ result: SearchCommunityResult) {
        blockedResults.append(result)
    }

    func communityIsNotifying(_: SearchCommunityResult) -> Bool {
        isNotifying
    }

    func communityToggleNotify(_ result: SearchCommunityResult) {
        toggleNotifyResults.append(result)
    }

    func communityFavoriteState(_: SearchCommunityResult) -> Bool? {
        favoriteState
    }

    func communityToggleFavorite(_ result: SearchCommunityResult) {
        toggleFavoriteResults.append(result)
    }
}

/// A second, deliberately minimal `CommunityContextMenuHost` fake that
/// implements only the non-defaulted protocol requirements - it does NOT
/// override `communityFavoriteState`/`communityToggleFavorite`, so it
/// exercises the protocol-extension defaults exactly as Search's real host
/// does today. Used to assert the builder omits the Favourite action
/// entirely when a surface hasn't opted in.
@MainActor
final class DefaultCommunityContextMenuHost: UIViewController, CommunityContextMenuHost {
    func communityOpen(_: SearchCommunityResult) { }
    func communitySetSubscribed(_: SearchCommunityResult, subscribed: Bool) { }
    func communityIsMuted(_: SearchCommunityResult) -> Bool {
        false
    }

    func communityMute(_: SearchCommunityResult, duration: MuteDuration) { }
    func communityUnmute(_: SearchCommunityResult) { }
    func communityShare(_: SearchCommunityResult) { }
    func communityCopyLink(_: SearchCommunityResult) { }
    func communityBlock(_: SearchCommunityResult) { }
    func communityIsNotifying(_: SearchCommunityResult) -> Bool {
        false
    }

    func communityToggleNotify(_: SearchCommunityResult) { }
}

/// Minimal `SearchCommunityResult` test factory.
extension SearchCommunityResult {
    static func fixture(
        serverCommunityId: Lemmy.CommunityID = 1,
        name: String = "tincidunt",
        followState: FollowState = .notFollowing,
        isNsfw: Bool = false,
        communityUrl: String = "https://lemmy.world/c/tincidunt"
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
            communityUrl: communityUrl
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

    /// Recursively locates the `UIAction` titled `title`, if any - used to
    /// inspect an action's `state` (checkmark) rather than just perform it.
    private func findAction(titled title: String, in menu: UIMenu) -> UIAction? {
        for element in menu.children {
            if let action = element as? UIAction, action.title == title {
                return action
            }
            if let submenu = element as? UIMenu, let found = findAction(titled: title, in: submenu) {
                return found
            }
        }
        return nil
    }

    @Test
    func includesCoreActionsWhenNotSubscribedNotMuted() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .notFollowing)
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
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
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        let titles = allTitles(menu)
        #expect(titles.contains("Unsubscribe"))
        #expect(!titles.contains("Subscribe"))
    }

    /// The resolved `subscribedState` param — not `result.followState` — decides
    /// the label. A community with an in-flight approval request has a network
    /// `followState` of `.notFollowing` (v3 collapses "approval required" away)
    /// but a resolved `.pending` state (the persisted DB truth); the menu must
    /// still show "Unsubscribe" so a long-press offers to cancel the pending
    /// request rather than re-offering "Subscribe".
    @Test
    func showsUnsubscribeWhenResolvedStatePending_evenWhenNetworkFollowStateIsNotFollowing() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .notFollowing)
        let menu = CommunityContextMenuBuilder.menu(for: result, subscribedState: .pending, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Unsubscribe"))
        #expect(!titles.contains("Subscribe"))
    }

    /// The mirror image: a resolved `.notSubscribed` state shows "Subscribe"
    /// regardless of what the network response says.
    @Test
    func showsSubscribeWhenResolvedStateNotSubscribed() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .accepted)
        let menu = CommunityContextMenuBuilder.menu(for: result, subscribedState: .notSubscribed, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Subscribe"))
        #expect(!titles.contains("Unsubscribe"))
    }

    @Test
    func showsUnmuteWhenMuted() {
        let host = FakeCommunityContextMenuHost()
        host.isMuted = true
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        let titles = allTitles(menu)
        #expect(titles.contains("Unmute"))
        #expect(!titles.contains("Mute"))
    }

    @Test
    func openCommunityInvokesHostOpen() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: "Open Community", in: menu)
        #expect(host.openedResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func subscribeInvokesHostSetSubscribed() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .notFollowing)
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: "Subscribe", in: menu)
        #expect(host.subscribedCalls.count == 1)
        #expect(host.subscribedCalls.first?.subscribed == true)
    }

    @Test
    func unsubscribeInvokesHostSetSubscribed() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture(followState: .accepted)
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: "Unsubscribe", in: menu)
        #expect(host.subscribedCalls.count == 1)
        #expect(host.subscribedCalls.first?.subscribed == false)
    }

    @Test
    func unmuteInvokesHostUnmute() {
        let host = FakeCommunityContextMenuHost()
        host.isMuted = true
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: "Unmute", in: menu)
        #expect(host.unmutedResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func shareInvokesHostShare() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: "Share", in: menu)
        #expect(host.sharedResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func copyLinkInvokesHostCopyLink() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: "Copy Link", in: menu)
        #expect(host.copiedLinkResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func blockInvokesHostBlock() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: "Block Community", in: menu)
        #expect(host.blockedResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func includesNotifyAction() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        #expect(allTitles(menu).contains(CommunityNotifyLabel.title))
    }

    /// The notify action's checkmark reflects `host.communityIsNotifying`,
    /// resolved at menu-build time (mirrors the mute/subscribe state reads
    /// above).
    @Test
    func notifyAction_stateReflectsHostIsNotifying_off() {
        let host = FakeCommunityContextMenuHost()
        host.isNotifying = false
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        #expect(findAction(titled: CommunityNotifyLabel.title, in: menu)?.state == .off)
    }

    @Test
    func notifyAction_stateReflectsHostIsNotifying_on() {
        let host = FakeCommunityContextMenuHost()
        host.isNotifying = true
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        #expect(findAction(titled: CommunityNotifyLabel.title, in: menu)?.state == .on)
    }

    @Test
    func notifyActionInvokesHostToggleNotify() {
        let host = FakeCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        performAction(titled: CommunityNotifyLabel.title, in: menu)
        #expect(host.toggleNotifyResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    /// A host that doesn't override `communityFavoriteState` (Search's real
    /// host today) inherits the protocol-extension default of `nil`, which
    /// means the surface doesn't offer Favourite at all - the builder must
    /// omit the action entirely, not just leave it in some default state.
    @Test
    func defaultHost_omitsFavoriteAction() {
        let host = DefaultCommunityContextMenuHost()
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        let titles = allTitles(menu)
        #expect(!titles.contains(CommunityFavoriteLabel.title(isFavorited: false)))
        #expect(!titles.contains(CommunityFavoriteLabel.title(isFavorited: true)))
    }

    @Test
    func favoriteState_false_showsAddToFavoritesAndInvokesToggle() {
        let host = FakeCommunityContextMenuHost()
        host.favoriteState = false
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        let title = CommunityFavoriteLabel.title(isFavorited: false)
        #expect(allTitles(menu).contains(title))
        performAction(titled: title, in: menu)
        #expect(host.toggleFavoriteResults.map(\.serverCommunityId) == [result.serverCommunityId])
    }

    @Test
    func favoriteState_true_showsRemoveFromFavorites() {
        let host = FakeCommunityContextMenuHost()
        host.favoriteState = true
        let result = SearchCommunityResult.fixture()
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        let title = CommunityFavoriteLabel.title(isFavorited: true)
        #expect(allTitles(menu).contains(title))
        #expect(!allTitles(menu).contains(CommunityFavoriteLabel.title(isFavorited: false)))
    }

    /// Menu order in the open group: Open, Subscribe, Favourite (when
    /// present), Notify.
    @Test
    func favoriteAction_isOrderedBetweenSubscribeAndNotify() {
        let host = FakeCommunityContextMenuHost()
        host.favoriteState = false
        let result = SearchCommunityResult.fixture(followState: .notFollowing)
        let menu = CommunityContextMenuBuilder.menu(
            for: result,
            subscribedState: CommunitySubscribedState(followState: result.followState),
            host: host
        )
        let titles = allTitles(menu)
        let subscribeIndex = titles.firstIndex(of: "Subscribe")
        let favoriteIndex = titles.firstIndex(of: CommunityFavoriteLabel.title(isFavorited: false))
        let notifyIndex = titles.firstIndex(of: CommunityNotifyLabel.title)
        #expect(subscribeIndex != nil)
        #expect(favoriteIndex != nil)
        #expect(notifyIndex != nil)
        if let subscribeIndex, let favoriteIndex, let notifyIndex {
            #expect(subscribeIndex < favoriteIndex)
            #expect(favoriteIndex < notifyIndex)
        }
    }
}
