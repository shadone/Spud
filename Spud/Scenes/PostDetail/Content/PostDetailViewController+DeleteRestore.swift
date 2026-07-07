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

/// Delete / restore / edit of the user's own post and comments, hosted on
/// `PostDetailViewController`.
///
/// Invoked from the header/comment context and moderation menus in the main
/// file. Deleting prompts for confirmation (restoring does not); the actual
/// mutation is enqueued optimistically through the account's `LemmyService` /
/// outbox, so the open screen reflects it via its GRDB observation and a
/// permanent failure rolls back and surfaces via the failure stream. Editing an
/// own comment reopens the composer seeded with the current body.
extension PostDetailViewController {
    // MARK: - Delete / Restore (own comment)

    /// Confirm deleting the user's own comment, then enqueue the optimistic
    /// delete through the outbox. Restoring needs no confirmation.
    func promptDeleteComment(serverCommentId: Int64) {
        let alert = UIAlertController(
            title: NSLocalizedString("Delete comment?", comment: "Confirmation title for deleting the user's own comment"),
            message: NSLocalizedString("This removes the comment for everyone. You can restore it later.", comment: "Confirmation message for deleting the user's own comment"),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Delete", comment: "Destructive confirm button to delete the user's own comment"),
            style: .destructive
        ) { [weak self] _ in
            self?.setDeletedOnComment(serverCommentId: serverCommentId, deleted: true)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        // iPad: anchor the popover to avoid a regular-width crash.
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    /// Opens the composer in edit mode for the user's own comment, seeded with
    /// its current body. Saving enqueues an optimistic edit to the content outbox.
    func editOwnComment(serverCommentId: Int64, currentBody: String) {
        presentComposer(
            target: .editComment(
                serverPostId: viewModel.serverPostId,
                serverCommentId: Lemmy.CommentID(serverCommentId)
            ),
            initialBody: currentBody
        )
    }

    func setDeletedOnComment(serverCommentId: Int64, deleted: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel.deleteComment(serverCommentId: serverCommentId, deleted: deleted)
            } catch {
                // The optimistic write already applied synchronously inside
                // enqueue; network failures are retried by the outbox and a
                // permanent failure rolls back + surfaces via the failure stream.
                alertService.handle(error, for: .deleteComment)
            }
        }
    }

    // MARK: - Delete / Restore (own post)

    /// Confirm deleting the user's own post, then enqueue the optimistic delete
    /// through the outbox. Restoring needs no confirmation.
    func promptDeletePost(serverPostId: Lemmy.PostID) {
        let alert = UIAlertController(
            title: NSLocalizedString("Delete post?", comment: "Confirmation title for deleting the user's own post"),
            message: NSLocalizedString(
                "This removes the post for everyone. You can restore it later.",
                comment: "Confirmation message for deleting the user's own post"
            ),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Delete", comment: "Destructive confirm button to delete the user's own post"),
            style: .destructive
        ) { [weak self] _ in
            self?.setDeletedOnPost(serverPostId: serverPostId, deleted: true)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        // iPad: anchor the popover to avoid a regular-width crash.
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    func setDeletedOnPost(serverPostId: Lemmy.PostID, deleted: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel.deletePost(serverPostId: serverPostId, deleted: deleted)
            } catch {
                // The optimistic write already applied synchronously inside
                // enqueue; network failures are retried by the outbox and a
                // permanent failure rolls back + surfaces via the failure stream.
                alertService.handle(error, for: .deletePost)
            }
        }
    }
}
