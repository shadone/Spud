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

/// A fake `PostContextMenuHost` driving the builder in isolation. `vote(...)`
/// overrides the `PostVoteDispatching` default to record the call instead of
/// dispatching through the outbox; `postActionsAccountScope` /
/// `postActionsAlertService` / `appDatabase` are wired to a real in-memory
/// `AccountService` + `AppDatabase` (the same pattern `PostListViewModel*Tests`
/// uses) rather than a hand-rolled `AccountServiceType` double, since none of
/// these tests exercise vote/save/reminder dispatch through them.
@MainActor
final class FakePostContextMenuHost: UIViewController, PostContextMenuHost {
    var row: PostListRow
    private(set) var votedPostIds: [Int64] = []
    private(set) var shareAsImageServerPostIds: [Int64] = []

    private let appDatabaseBacking: AppDatabase
    private let accountScopeBacking: AccountScope

    init(row: PostListRow) {
        self.row = row
        let appDatabase = try! AppDatabase.inMemory()
        appDatabaseBacking = appDatabase
        let accountService = AccountService(appDatabase: appDatabase)
        accountScopeBacking = accountService.scope(forAccountKeychainId: "kc-post-context-menu-test")
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    /// PostVoteDispatching / PostSaveDispatching
    var postActionsAccountScope: AccountScope {
        accountScopeBacking
    }

    var postActionsAlertService: AlertServiceType {
        AlertService()
    }

    func currentSavedState(serverPostId _: Int64) -> Bool {
        row.isSaved
    }

    func vote(serverPostId: Int64, action _: VoteStatus.Action) async {
        votedPostIds.append(serverPostId)
    }

    /// PostReminderDispatching
    var appDatabase: AppDatabase {
        appDatabaseBacking
    }

    func remindMeMenuDidChange() { }

    /// PostContextMenuHost
    func postContextRow(forServerPostId _: Int64) -> PostListRow? {
        row
    }

    func remindMeMenuTarget(serverPostId _: Int64) -> RemindMeMenuTarget? {
        nil
    }

    func postReply(serverPostId _: Int64) { }
    func postShare(serverPostId _: Int64) { }
    func postShareAsImage(serverPostId: Int64) {
        shareAsImageServerPostIds.append(serverPostId)
    }

    func postCrossPost(serverPostId _: Int64) { }
    func postVisitCommunity(serverPostId _: Int64) { }
    func postViewAuthor(serverPostId _: Int64) { }
    func postHide(serverPostId _: Int64) { }
    func postBlockAuthor(serverPostId _: Int64) { }
    func postReport(serverPostId _: Int64) { }
    func postMuteCommunity(serverPostId _: Int64, duration _: MuteDuration) { }
}

/// Minimal `PostListRow` test factory: `SpudTests` doesn't have one yet
/// (checked with `grep -rn "extension PostListRow" SpudTests/`), so this adds
/// the fields the builder actually reads (community/creator handle + saved
/// state) with neutral defaults for the rest.
extension PostListRow {
    static func fixture(
        serverPostId: Int64 = 1,
        communityName: String = "community",
        communityActorId: String? = "https://example.com/c/community",
        creatorName: String? = nil,
        creatorActorId: String? = "https://example.com/u/creator",
        isSaved: Bool = false,
        isLocked: Bool = false
    ) -> PostListRow {
        PostListRow(
            id: serverPostId,
            serverPostId: serverPostId,
            title: "Test post",
            body: nil,
            originalPostUrl: "https://example.com/post/\(serverPostId)",
            url: nil,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: communityName,
            communityActorId: communityActorId,
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: creatorName,
            creatorActorId: creatorActorId,
            score: 0,
            numberOfComments: 0,
            voteStatus: nil,
            isRead: false,
            isSaved: isSaved,
            isRemoved: false,
            isLocked: isLocked,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            published: Date(timeIntervalSince1970: 0)
        )
    }
}

@MainActor
struct PostContextMenuBuilderTests {
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
            return false
        }
    }

    @Test
    func includesCoreActionsAndDestructiveSafety() throws {
        let host = FakePostContextMenuHost(row: .fixture(communityName: "news", creatorName: "alice", isSaved: false))
        let menu = PostContextMenuBuilder.menu(forServerPostId: 42, host: host, upvoteIcon: nil, downvoteIcon: nil)
        let titles = allTitles(menu)
        #expect(titles.contains("Upvote"))
        #expect(titles.contains("Downvote"))
        #expect(titles.contains("Save"))
        #expect(titles.contains("Reply"))
        #expect(titles.contains("Share"))
        #expect(titles.contains("Share as Image"))
        // "Share as Image" sits immediately after "Share" in the share group.
        // #require (not `if let`) so the adjacency assertion can never silently
        // skip if "Share" is missing.
        let shareIndex = try #require(titles.firstIndex(of: "Share"))
        #expect(titles[titles.index(after: shareIndex)] == "Share as Image")
        #expect(titles.contains("Cross-post"))
        #expect(titles.contains("Visit c/news"))
        #expect(titles.contains("View u/alice"))
        #expect(titles.contains("Hide"))
        #expect(hasDestructive(menu, title: "Block u/alice"))
        #expect(hasDestructive(menu, title: "Report"))
    }

    @Test
    func omitsReplyWhenPostIsLocked() {
        let host = FakePostContextMenuHost(row: .fixture(communityName: "news", creatorName: "alice", isLocked: true))
        let menu = PostContextMenuBuilder.menu(forServerPostId: 1, host: host, upvoteIcon: nil, downvoteIcon: nil)
        let titles = allTitles(menu)
        #expect(!titles.contains("Reply"))
        // Every other action stays untouched: locking a post never touches
        // vote/save/hide/share/open/moderation.
        #expect(titles.contains("Upvote"))
        #expect(titles.contains("Downvote"))
        #expect(titles.contains("Save"))
        #expect(titles.contains("Share"))
        #expect(titles.contains("Share as Image"))
        #expect(titles.contains("Cross-post"))
        #expect(titles.contains("Visit c/news"))
        #expect(titles.contains("View u/alice"))
        #expect(titles.contains("Hide"))
        #expect(hasDestructive(menu, title: "Block u/alice"))
        #expect(hasDestructive(menu, title: "Report"))
    }

    @Test
    func includesReplyWhenPostIsNotLocked() {
        let host = FakePostContextMenuHost(row: .fixture(isLocked: false))
        let menu = PostContextMenuBuilder.menu(forServerPostId: 1, host: host, upvoteIcon: nil, downvoteIcon: nil)
        #expect(allTitles(menu).contains("Reply"))
    }

    @Test
    func saveTitleReflectsSavedState() {
        let host = FakePostContextMenuHost(row: .fixture(isSaved: true))
        let menu = PostContextMenuBuilder.menu(forServerPostId: 1, host: host, upvoteIcon: nil, downvoteIcon: nil)
        #expect(allTitles(menu).contains("Unsave"))
    }

    @Test
    func omitsFeedOnlySubmenusWhenHostReturnsNil() {
        // A host that provides no cross-post siblings and no moderation (the
        // Search case) yields a menu without those submenus.
        let host = FakePostContextMenuHost(row: .fixture())
        let menu = PostContextMenuBuilder.menu(forServerPostId: 1, host: host, upvoteIcon: nil, downvoteIcon: nil)
        let titles = allTitles(menu)
        #expect(!titles.contains("Also posted in"))
    }

    @Test
    func upvoteInvokesHostVote() async {
        let host = FakePostContextMenuHost(row: .fixture())
        let menu = PostContextMenuBuilder.menu(forServerPostId: 7, host: host, upvoteIcon: nil, downvoteIcon: nil)
        // Locate and perform the Upvote action's handler.
        performAction(titled: "Upvote", in: menu)
        // The fake records the vote call synchronously via the Task; yield once.
        await Task.yield()
        #expect(host.votedPostIds.contains(7))
    }

    @Test
    func shareAsImageInvokesHost() {
        let host = FakePostContextMenuHost(row: .fixture())
        let menu = PostContextMenuBuilder.menu(forServerPostId: 9, host: host, upvoteIcon: nil, downvoteIcon: nil)
        performAction(titled: "Share as Image", in: menu)
        #expect(host.shareAsImageServerPostIds == [9])
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
}
