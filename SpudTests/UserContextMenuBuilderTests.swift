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

/// A fake `UserContextMenuHost` driving the builder in isolation, recording
/// every call instead of dispatching through `LemmyService` / the sign-in gate.
@MainActor
final class FakeUserContextMenuHost: UIViewController, UserContextMenuHost {
    private(set) var openedResults: [SearchUserResult] = []
    private(set) var copiedHandleResults: [SearchUserResult] = []
    private(set) var sharedResults: [SearchUserResult] = []
    private(set) var blockedCalls: [(result: SearchUserResult, blocked: Bool)] = []

    func userOpen(_ result: SearchUserResult) {
        openedResults.append(result)
    }

    func userCopyHandle(_ result: SearchUserResult) {
        copiedHandleResults.append(result)
    }

    func userShare(_ result: SearchUserResult) {
        sharedResults.append(result)
    }

    func userSetBlocked(_ result: SearchUserResult, blocked: Bool) {
        blockedCalls.append((result, blocked))
    }
}

/// Minimal `SearchUserResult` test factory.
extension SearchUserResult {
    static func fixture(
        serverPersonId: Lemmy.PersonID = 1,
        name: String = "alice",
        instance: InstanceActorId = InstanceActorId(from: "lemmy.world")!
    ) -> SearchUserResult {
        SearchUserResult(
            serverPersonId: serverPersonId,
            name: name,
            qualifiedName: "@\(name)@\(instance.hostWithPort)",
            instance: instance,
            avatarUrl: nil
        )
    }
}

@MainActor
struct UserContextMenuBuilderTests {
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
    func includesCoreActionsWhenNotBlocked() {
        let host = FakeUserContextMenuHost()
        let result = SearchUserResult.fixture()
        let menu = UserContextMenuBuilder.menu(for: result, isBlocked: false, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Open profile"))
        #expect(titles.contains("Copy handle"))
        #expect(titles.contains("Share"))
        #expect(hasDestructive(menu, title: "Block user"))
        #expect(!titles.contains("Unblock user"))
    }

    @Test
    func showsUnblockWhenBlocked() {
        let host = FakeUserContextMenuHost()
        let result = SearchUserResult.fixture()
        let menu = UserContextMenuBuilder.menu(for: result, isBlocked: true, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Unblock user"))
        #expect(!titles.contains("Block user"))
        #expect(!hasDestructive(menu, title: "Unblock user"))
    }

    @Test
    func openInvokesHostOpen() {
        let host = FakeUserContextMenuHost()
        let result = SearchUserResult.fixture()
        let menu = UserContextMenuBuilder.menu(for: result, isBlocked: false, host: host)
        performAction(titled: "Open profile", in: menu)
        #expect(host.openedResults.map(\.serverPersonId) == [result.serverPersonId])
    }

    @Test
    func copyHandleInvokesHost() {
        let host = FakeUserContextMenuHost()
        let result = SearchUserResult.fixture()
        let menu = UserContextMenuBuilder.menu(for: result, isBlocked: false, host: host)
        performAction(titled: "Copy handle", in: menu)
        #expect(host.copiedHandleResults.map(\.serverPersonId) == [result.serverPersonId])
    }

    @Test
    func shareInvokesHost() {
        let host = FakeUserContextMenuHost()
        let result = SearchUserResult.fixture()
        let menu = UserContextMenuBuilder.menu(for: result, isBlocked: false, host: host)
        performAction(titled: "Share", in: menu)
        #expect(host.sharedResults.map(\.serverPersonId) == [result.serverPersonId])
    }

    @Test
    func blockInvokesHostSetBlockedTrue() {
        let host = FakeUserContextMenuHost()
        let result = SearchUserResult.fixture()
        let menu = UserContextMenuBuilder.menu(for: result, isBlocked: false, host: host)
        performAction(titled: "Block user", in: menu)
        #expect(host.blockedCalls.count == 1)
        #expect(host.blockedCalls.first?.blocked == true)
    }

    @Test
    func unblockInvokesHostSetBlockedFalse() {
        let host = FakeUserContextMenuHost()
        let result = SearchUserResult.fixture()
        let menu = UserContextMenuBuilder.menu(for: result, isBlocked: true, host: host)
        performAction(titled: "Unblock user", in: menu)
        #expect(host.blockedCalls.count == 1)
        #expect(host.blockedCalls.first?.blocked == false)
    }
}
