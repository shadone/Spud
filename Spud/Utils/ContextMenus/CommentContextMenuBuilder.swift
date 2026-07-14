//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import UIKit

/// The per-screen action surface a `CommentContextMenuBuilder` menu drives.
/// Search's `.comment` result rows conform so a long-press comment gets the
/// primary actions from `PostDetailViewController`'s comment context menu
/// (`PostDetailViewController.swift:2177-2298`), adapted to a search result's
/// live per-viewer `SearchCommentResult` rather than a loaded
/// `PostDetailCommentRow`. Own-comment Edit/Delete and the moderation submenu
/// are deliberately OUT of scope for this first cut — search has no notion of
/// "is this my comment" or a moderation capability at the result-row level.
@MainActor
protocol CommentContextMenuHost: UIViewController {
    /// Opens the comment's parent post. Search has no in-app "jump to
    /// comment" entry point, so this opens the whole thread the same way a
    /// plain row tap does.
    func commentOpenThread(_ result: SearchCommentResult)
    /// Casts or clears a vote on the comment, through the same per-account
    /// `LemmyService.vote(serverCommentId:vote:)` call
    /// `PostDetailViewController.voteOnComment` dispatches.
    func commentVote(_ result: SearchCommentResult, direction: VoteStatus.Action) async
    /// Saves or unsaves the comment, through the same
    /// `LemmyService.setSaved(serverCommentId:saved:)` call
    /// `PostDetailViewController.setSavedOnComment` dispatches.
    func commentToggleSave(_ result: SearchCommentResult)
    func commentShare(_ result: SearchCommentResult)
    func commentCopyLink(_ result: SearchCommentResult)
    func commentViewAuthor(_ result: SearchCommentResult)
    func commentReport(_ result: SearchCommentResult)
}

/// Builds the long-press menu for a Search `.comment` result. Mirrors
/// `PostDetailViewController`'s comment context menu for the actions this
/// first cut covers (Open thread, Upvote/Downvote, Save/Unsave, Share, Copy
/// Link, View author, Report) — own-comment Edit/Delete and moderation are
/// out of scope (see the host protocol's doc comment). Pure: every action
/// calls back into `host`; the builder performs no side effects itself.
@MainActor
enum CommentContextMenuBuilder {
    static func menu(
        for result: SearchCommentResult,
        host: CommentContextMenuHost,
        upvoteIcon: UIImage?,
        downvoteIcon: UIImage?
    ) -> UIMenu {
        let openThreadAction = UIAction(
            title: NSLocalizedString("Open Thread", comment: "Context-menu action to open a comment's parent post thread"),
            image: UIImage(systemName: "bubble.left.and.bubble.right")
        ) { [weak host] _ in host?.commentOpenThread(result) }
        let openGroup = UIMenu(options: .displayInline, children: [openThreadAction])

        // Plain vote actions (title + image + handler), matching
        // `PostContextMenuBuilder`'s Upvote/Downvote so a long-press shows the
        // same chrome for a comment result as for a post result. Voted state is
        // expressed structurally elsewhere (list pill / comment mini-pill), not
        // via a menu checkmark, and `SearchViewModel.results` is a static
        // snapshot that wouldn't refresh a checkmark mid-session anyway.
        let upvoteAction = UIAction(
            title: NSLocalizedString("Upvote", comment: ""),
            image: upvoteIcon
        ) { [weak host] _ in
            Task { await host?.commentVote(result, direction: .upvote) }
        }
        let downvoteAction = UIAction(
            title: NSLocalizedString("Downvote", comment: ""),
            image: downvoteIcon
        ) { [weak host] _ in
            Task { await host?.commentVote(result, direction: .downvote) }
        }
        let saveAction = UIAction(
            title: result.isSaved
                ? NSLocalizedString("Unsave", comment: "Context-menu action to unsave a comment")
                : NSLocalizedString("Save", comment: "Context-menu action to save a comment"),
            image: UIImage(systemName: result.isSaved ? "bookmark.slash" : "bookmark")
        ) { [weak host] _ in host?.commentToggleSave(result) }
        let voteGroup = UIMenu(options: .displayInline, children: [upvoteAction, downvoteAction, saveAction])

        let shareAction = UIAction(
            title: NSLocalizedString("Share", comment: "Context-menu action to share a comment"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak host] _ in host?.commentShare(result) }
        let copyAction = UIAction(
            title: NSLocalizedString("Copy Link", comment: "Context-menu action to copy a comment's link"),
            image: UIImage(systemName: "link")
        ) { [weak host] _ in host?.commentCopyLink(result) }
        let shareGroup = UIMenu(options: .displayInline, children: [shareAction, copyAction])

        let viewAuthorAction = UIAction(
            title: String(
                format: NSLocalizedString("View %@", comment: "Context-menu action to open a comment author's profile; %@ is the u/ author handle"),
                "u/\(result.creatorName)"
            ),
            image: UIImage(systemName: "person.crop.circle")
        ) { [weak host] _ in host?.commentViewAuthor(result) }
        let viewAuthorGroup = UIMenu(options: .displayInline, children: [viewAuthorAction])

        let reportAction = UIAction(
            title: NSLocalizedString("Report", comment: "Context-menu action to report a comment"),
            image: UIImage(systemName: "flag"),
            attributes: .destructive
        ) { [weak host] _ in host?.commentReport(result) }
        let reportGroup = UIMenu(options: .displayInline, children: [reportAction])

        return UIMenu(title: "", children: [openGroup, voteGroup, shareGroup, viewAuthorGroup, reportGroup])
    }
}
