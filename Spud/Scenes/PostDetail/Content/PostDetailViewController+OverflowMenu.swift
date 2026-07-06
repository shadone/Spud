//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// The nav-bar "•••" overflow menu, hosted on `PostDetailViewController`.
///
/// `makePostOverflowMenu` is rebuilt from the current `viewModel.headerRow`
/// whenever the row changes (see the header reaction loop in the main file), so the
/// Save/Unsave label, the Mute target, and the own-post-gated Report / Block /
/// Edit / Delete items always reflect the latest state. The comment / save /
/// share / edit / delete actions delegate back to the main file and sibling
/// seams; muting and blocking are handled here.
extension PostDetailViewController {
    // MARK: - Overflow menu

    /// Builds the nav-bar "•••" overflow menu from the current `viewModel.headerRow`.
    /// Rebuilt whenever the row changes (see the header reaction loop), so the
    /// Save/Unsave label, the Mute target, and the own-post-gated Report /
    /// Block items always reflect the latest state. Grouped with inline
    /// submenus so each section renders with a divider, matching the design.
    func makePostOverflowMenu() -> UIMenu {
        let isSaved = viewModel.headerRow?.isSaved ?? false

        let addCommentAction = UIAction(
            title: NSLocalizedString("Add comment", comment: "Overflow-menu action to comment on a post"),
            image: UIImage(systemName: "plus.bubble")
        ) { [weak self] _ in
            self?.replyToPost()
        }
        let saveAction = UIAction(
            title: isSaved
                ? NSLocalizedString("Unsave", comment: "Overflow-menu action to unsave a post")
                : NSLocalizedString("Save", comment: "Overflow-menu action to save a post"),
            image: UIImage(systemName: isSaved ? "bookmark.slash" : "bookmark")
        ) { [weak self] _ in
            guard let self else { return }
            toggleSaved(serverPostId: Int64(viewModel.serverPostId))
        }
        let shareAction = UIAction(
            title: NSLocalizedString("Share", comment: "Overflow-menu action to share a post"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.sharePost()
        }
        let selectTextAction = UIAction(
            title: NSLocalizedString("Select Text", comment: "Overflow-menu action to select the post's text"),
            image: UIImage(systemName: "character.cursor.ibeam")
        ) { [weak self] _ in
            self?.presentTextSelection()
        }
        let primaryGroup = UIMenu(
            options: .displayInline,
            children: [addCommentAction, saveAction, shareAction, selectTextAction]
        )

        let openInBrowserAction = UIAction(
            title: NSLocalizedString("Open in Browser", comment: "Overflow-menu action to open the post in a browser"),
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            self?.openInBrowser()
        }
        var utilityChildren: [UIMenuElement] = [openInBrowserAction]
        if
            let communityActorId = viewModel.headerRow?.communityActorId,
            let communityName = viewModel.headerRow?.communityName, !communityName.isEmpty
        {
            utilityChildren.append(makeMuteCommunityMenu(
                communityActorId: communityActorId,
                communityName: communityName
            ))
        }
        let utilityGroup = UIMenu(options: .displayInline, children: utilityChildren)

        var children: [UIMenuElement] = [primaryGroup, utilityGroup]

        // Report / Block only make sense on someone else's post.
        if !isOwnContent(creatorPersonId: viewModel.headerRow?.creatorPersonId), let row = viewModel.headerRow {
            let reportAction = UIAction(
                title: NSLocalizedString("Report", comment: "Overflow-menu action to report a post"),
                image: UIImage(systemName: "flag"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.reportPost()
            }
            let blockAction = UIAction(
                title: String(
                    format: NSLocalizedString("Block %@", comment: "Context-menu action to block a post author; %@ is the u/ author handle"),
                    "u/\(row.creatorName)"
                ),
                image: UIImage(systemName: "hand.raised"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.blockAuthor()
            }
            children.append(UIMenu(options: .displayInline, children: [reportAction, blockAction]))
        }

        // Edit / Delete / Restore only make sense on the user's own post.
        if isOwnContent(creatorPersonId: viewModel.headerRow?.creatorPersonId) {
            let currentlyDeleted = viewModel.headerRow?.isDeleted ?? false
            var ownActions: [UIMenuElement] = []
            // Editing a deleted post isn't offered (restore it first).
            if !currentlyDeleted {
                ownActions.append(UIAction(
                    title: NSLocalizedString("Edit", comment: "Overflow-menu action to edit the user's own post"),
                    image: UIImage(systemName: "pencil")
                ) { [weak self] _ in
                    self?.presentEditPost()
                })
            }
            let deleteAction = UIAction(
                title: currentlyDeleted
                    ? NSLocalizedString("Restore", comment: "Overflow-menu action to restore the user's own deleted post")
                    : NSLocalizedString("Delete", comment: "Overflow-menu action to delete the user's own post"),
                image: UIImage(systemName: currentlyDeleted ? "arrow.uturn.backward" : "trash"),
                attributes: currentlyDeleted ? [] : .destructive
            ) { [weak self] _ in
                guard let self else { return }
                if currentlyDeleted {
                    setDeletedOnPost(serverPostId: viewModel.serverPostId, deleted: false)
                } else {
                    promptDeletePost(serverPostId: viewModel.serverPostId)
                }
            }
            ownActions.append(deleteAction)
            children.append(UIMenu(options: .displayInline, children: ownActions))
        }

        return UIMenu(title: "", children: children)
    }

    /// The "Mute c/<community> >" submenu offering the timed durations. Muting
    /// is a client-local view concern, so it isn't sign-in gated.
    private func makeMuteCommunityMenu(communityActorId: String, communityName: String) -> UIMenu {
        let actions = MuteDuration.allCases.map { duration in
            UIAction(title: duration.menuTitle) { [weak self] _ in
                self?.muteCommunity(communityActorId: communityActorId, duration: duration)
            }
        }
        return UIMenu(
            title: String(
                format: NSLocalizedString("Mute %@", comment: "Context-menu action to mute a community; %@ is the c/ community handle"),
                "c/\(communityName)"
            ),
            image: UIImage(systemName: "bell.slash"),
            children: actions
        )
    }

    private func muteCommunity(communityActorId: String, duration: MuteDuration) {
        Haptics.tap()
        appDatabase.muteCommunitySync(
            forKeychainId: viewModel.accountKeychainId,
            communityActorId: communityActorId,
            until: duration.until
        )
    }

    /// Blocks the post's author, gating on sign-in and confirming first.
    private func blockAuthor() {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block")
            )
            return
        }
        guard let row = viewModel.headerRow else { return }
        presentDestructiveConfirmation(
            title: String(format: NSLocalizedString("Block %@?", comment: "Block user confirmation title"), row.creatorName),
            message: NSLocalizedString(
                "You won't see posts or comments from this user. You can unblock them later.",
                comment: "Block user confirmation message"
            ),
            confirmTitle: NSLocalizedString("Block", comment: "Block user confirm button"),
            sourceItem: overflowBarButtonItem
        ) { [weak self] in
            Task { await self?.submitBlockAuthor(serverPersonId: row.creatorPersonId) }
        }
    }

    private func submitBlockAuthor(serverPersonId: Int64) async {
        do {
            try await viewModel.accountScope.lemmyService
                .setBlocked(serverPersonId: Components.Schemas.PersonID(serverPersonId), blocked: true)
        } catch {
            alertService.handle(error, for: .setBlockedPerson)
        }
    }

    /// Presents the post's title and body as selectable, copyable text.
    private func presentTextSelection() {
        guard let row = viewModel.headerRow else {
            Haptics.warning()
            return
        }
        let textViewController = SelectableTextViewController(title: row.title, body: row.body)
        present(UINavigationController(rootViewController: textViewController), animated: true)
    }
}
