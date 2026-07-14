//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// A fake `CommentContextMenuHost` driving the builder in isolation, recording
/// every call instead of dispatching through `LemmyService`.
@MainActor
final class FakeCommentContextMenuHost: UIViewController, CommentContextMenuHost {
    private(set) var openedResults: [SearchCommentResult] = []
    private(set) var votedCalls: [(result: SearchCommentResult, direction: VoteStatus.Action)] = []
    private(set) var toggledSaveResults: [SearchCommentResult] = []
    private(set) var sharedResults: [SearchCommentResult] = []
    private(set) var copiedLinkResults: [SearchCommentResult] = []
    private(set) var viewedAuthorResults: [SearchCommentResult] = []
    private(set) var reportedResults: [SearchCommentResult] = []

    func commentOpenThread(_ result: SearchCommentResult) {
        openedResults.append(result)
    }

    func commentVote(_ result: SearchCommentResult, direction: VoteStatus.Action) async {
        votedCalls.append((result, direction))
    }

    func commentToggleSave(_ result: SearchCommentResult) {
        toggledSaveResults.append(result)
    }

    func commentShare(_ result: SearchCommentResult) {
        sharedResults.append(result)
    }

    func commentCopyLink(_ result: SearchCommentResult) {
        copiedLinkResults.append(result)
    }

    func commentViewAuthor(_ result: SearchCommentResult) {
        viewedAuthorResults.append(result)
    }

    func commentReport(_ result: SearchCommentResult) {
        reportedResults.append(result)
    }
}

/// Minimal `SearchCommentResult` test factory.
extension SearchCommentResult {
    static func fixture(
        serverCommentId: Lemmy.CommentID = 1,
        serverPostId: Lemmy.PostID = 1,
        creatorName: String = "alice",
        creatorActorId: String? = "https://lemmy.world/u/alice",
        isSaved: Bool = false,
        myVote: VoteDirection = .none,
        originalCommentUrl: String? = "https://lemmy.world/comment/1"
    ) -> SearchCommentResult {
        SearchCommentResult(
            serverCommentId: serverCommentId,
            serverPostId: serverPostId,
            content: "A test comment",
            postTitle: "A test post",
            creatorName: creatorName,
            score: 1,
            published: Date(timeIntervalSince1970: 0),
            creatorPersonId: 1,
            creatorActorId: creatorActorId,
            communityName: "tincidunt",
            communityActorId: "https://lemmy.world/c/tincidunt",
            originalCommentUrl: originalCommentUrl,
            isSaved: isSaved,
            myVote: myVote
        )
    }
}

@MainActor
struct CommentContextMenuBuilderTests {
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
    func includesCoreActions() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture(creatorName: "alice", isSaved: false)
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        let titles = allTitles(menu)
        #expect(titles.contains("Open Thread"))
        #expect(titles.contains("Upvote"))
        #expect(titles.contains("Downvote"))
        #expect(titles.contains("Save"))
        #expect(!titles.contains("Unsave"))
        #expect(titles.contains("Share"))
        #expect(titles.contains("Copy Link"))
        #expect(titles.contains("View u/alice"))
        #expect(hasDestructive(menu, title: "Report"))
    }

    @Test
    func saveTitleReflectsSavedState() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture(isSaved: true)
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        let titles = allTitles(menu)
        #expect(titles.contains("Unsave"))
        #expect(!titles.contains("Save"))
    }

    @Test
    func openThreadInvokesHost() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture()
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Open Thread", in: menu)
        #expect(host.openedResults.map(\.serverCommentId) == [result.serverCommentId])
    }

    @Test
    func upvoteInvokesHostVote() async {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture()
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Upvote", in: menu)
        // The fake records the vote call inside a Task; yield once for it to run.
        await Task.yield()
        #expect(host.votedCalls.count == 1)
        #expect(host.votedCalls.first?.direction.description == "upvote")
    }

    @Test
    func downvoteInvokesHostVote() async {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture()
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Downvote", in: menu)
        await Task.yield()
        #expect(host.votedCalls.count == 1)
        #expect(host.votedCalls.first?.direction.description == "downvote")
    }

    @Test
    func saveInvokesHostToggleSave() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture()
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Save", in: menu)
        #expect(host.toggledSaveResults.map(\.serverCommentId) == [result.serverCommentId])
    }

    @Test
    func shareInvokesHostShare() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture()
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Share", in: menu)
        #expect(host.sharedResults.map(\.serverCommentId) == [result.serverCommentId])
    }

    @Test
    func copyLinkInvokesHostCopyLink() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture()
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Copy Link", in: menu)
        #expect(host.copiedLinkResults.map(\.serverCommentId) == [result.serverCommentId])
    }

    @Test
    func viewAuthorInvokesHostViewAuthor() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture(creatorName: "alice")
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "View u/alice", in: menu)
        #expect(host.viewedAuthorResults.map(\.serverCommentId) == [result.serverCommentId])
    }

    @Test
    func reportInvokesHostReport() {
        let host = FakeCommentContextMenuHost()
        let result = SearchCommentResult.fixture()
        let menu = CommentContextMenuBuilder.menu(for: result, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Report", in: menu)
        #expect(host.reportedResults.map(\.serverCommentId) == [result.serverCommentId])
    }
}
