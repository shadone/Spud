//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// A fake `InstanceContextMenuHost` driving the builder in isolation, recording
/// every call instead of pushing the instance screen / presenting the login flow.
@MainActor
final class FakeInstanceContextMenuHost: UIViewController, InstanceContextMenuHost {
    private(set) var openedResults: [SearchInstanceResult] = []
    private(set) var copiedLinkResults: [SearchInstanceResult] = []
    private(set) var sharedResults: [SearchInstanceResult] = []
    private(set) var addAccountResults: [SearchInstanceResult] = []

    func instanceOpen(_ result: SearchInstanceResult) {
        openedResults.append(result)
    }

    func instanceCopyLink(_ result: SearchInstanceResult) {
        copiedLinkResults.append(result)
    }

    func instanceShare(_ result: SearchInstanceResult) {
        sharedResults.append(result)
    }

    func instanceAddAccount(_ result: SearchInstanceResult) {
        addAccountResults.append(result)
    }
}

/// Minimal `SearchInstanceResult` test factory.
extension SearchInstanceResult {
    static func fixture(
        baseurl: String = "lemmy.world",
        name: String = "Lemmy World",
        usersTotal: Int64 = 5000
    ) -> SearchInstanceResult {
        SearchInstanceResult(record: ExplorerInstanceRecord(
            baseurl: baseurl,
            name: name,
            usersTotal: usersTotal
        ))
    }
}

@MainActor
struct InstanceContextMenuBuilderTests {
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
    func includesAllFourActions() {
        let host = FakeInstanceContextMenuHost()
        let result = SearchInstanceResult.fixture()
        let menu = InstanceContextMenuBuilder.menu(for: result, host: host)
        let titles = allTitles(menu)
        #expect(titles.contains("Open"))
        #expect(titles.contains("Copy Link"))
        #expect(titles.contains("Share"))
        #expect(titles.contains("Add Account Here"))
    }

    @Test
    func openInvokesHostOpen() {
        let host = FakeInstanceContextMenuHost()
        let result = SearchInstanceResult.fixture()
        let menu = InstanceContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Open", in: menu)
        #expect(host.openedResults.map(\.baseurl) == [result.baseurl])
    }

    @Test
    func copyLinkInvokesHost() {
        let host = FakeInstanceContextMenuHost()
        let result = SearchInstanceResult.fixture()
        let menu = InstanceContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Copy Link", in: menu)
        #expect(host.copiedLinkResults.map(\.baseurl) == [result.baseurl])
    }

    @Test
    func shareInvokesHost() {
        let host = FakeInstanceContextMenuHost()
        let result = SearchInstanceResult.fixture()
        let menu = InstanceContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Share", in: menu)
        #expect(host.sharedResults.map(\.baseurl) == [result.baseurl])
    }

    @Test
    func addAccountInvokesHost() {
        let host = FakeInstanceContextMenuHost()
        let result = SearchInstanceResult.fixture()
        let menu = InstanceContextMenuBuilder.menu(for: result, host: host)
        performAction(titled: "Add Account Here", in: menu)
        #expect(host.addAccountResults.map(\.baseurl) == [result.baseurl])
    }
}
