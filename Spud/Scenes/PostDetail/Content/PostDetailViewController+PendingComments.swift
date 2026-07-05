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

/// Tap handling for pending (optimistic) comment rows, hosted on
/// `PostDetailViewController`.
///
/// The tap handlers (`handlePendingTap` / `handleEditOverlayTap`) are invoked
/// from the comment cell-provider closures in the main file. Only a failed send
/// or edit is interactive, offering Retry / Edit / Discard through the account's
/// `LemmyService` composition queue. The synthetic-element-id maps they read
/// (`pendingTokenByElementId` / `pendingStateByElementId` /
/// `editOverlayByElementId`) stay on the main file, rebuilt each snapshot.
extension PostDetailViewController {
    // MARK: - Pending (optimistic) comment actions

    /// Handles a tap on a pending overlay comment. Only a failed send is
    /// interactive: it offers Retry (re-enqueue the same outbound row), Edit
    /// (discard then reopen the composer seeded with the failed text), and
    /// Discard (drop the outbound row).
    func handlePendingTap(elementId: Int64) {
        guard
            let token = pendingTokenByElementId[elementId],
            let state = pendingStateByElementId[elementId],
            state.status == .failed
        else { return }

        Haptics.tap()
        let sheet = UIAlertController(
            title: NSLocalizedString("Comment failed to send", comment: "Failed pending comment action sheet title"),
            message: state.body,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Retry", comment: "Retry a failed comment send"),
            style: .default
        ) { [weak self] _ in
            Task { await self?.viewModel.accountScope.lemmyService.retryComposition(clientToken: token) }
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Edit", comment: "Edit a failed comment before retrying"),
            style: .default
        ) { [weak self] _ in
            self?.editFailedComment(
                token: token,
                body: state.body,
                parentCommentServerId: state.parentCommentServerId
            )
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Discard", comment: "Discard a failed comment"),
            style: .destructive
        ) { [weak self] _ in
            Task { await self?.viewModel.accountScope.lemmyService.discardComposition(clientToken: token) }
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel the failed comment action sheet"),
            style: .cancel
        ))

        // iPad: anchor the popover to the tapped cell.
        if let popover = sheet.popoverPresentationController {
            if let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)),
               let cell = tableView.cellForRow(at: indexPath)
            {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        present(sheet, animated: true)
    }

    /// Handles a tap on a failed pending-EDIT overlay (a real comment row showing
    /// the locally-edited body with a failed indicator). Offers Retry (re-enqueue
    /// the edit) or Discard (drop the failed edit, reverting to the server body).
    func handleEditOverlayTap(elementId: Int64) {
        guard
            let overlay = editOverlayByElementId[elementId],
            overlay.status == .failed
        else { return }
        let token = overlay.clientToken

        Haptics.tap()
        let sheet = UIAlertController(
            title: NSLocalizedString("Edit failed to save", comment: "Failed pending comment edit action sheet title"),
            message: overlay.body,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Retry", comment: "Retry a failed comment edit"),
            style: .default
        ) { [weak self] _ in
            Task { await self?.viewModel.accountScope.lemmyService.retryComposition(clientToken: token) }
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Discard Edit", comment: "Discard a failed comment edit, reverting to the server body"),
            style: .destructive
        ) { [weak self] _ in
            Task { await self?.viewModel.accountScope.lemmyService.discardComposition(clientToken: token) }
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel the failed comment edit action sheet"),
            style: .cancel
        ))

        // iPad: anchor the popover to the tapped cell.
        if let popover = sheet.popoverPresentationController {
            if let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)),
               let cell = tableView.cellForRow(at: indexPath)
            {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        present(sheet, animated: true)
    }

    /// Edits a failed pending comment: discards the failed outbound row, then
    /// reopens the composer for the same target seeded with the failed text so
    /// the user never loses what they wrote.
    private func editFailedComment(token: String, body: String, parentCommentServerId: Int64?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await viewModel.accountScope.lemmyService.discardComposition(clientToken: token)
            if let parentCommentServerId {
                presentComposer(
                    target: .commentReply(
                        serverPostId: viewModel.serverPostId,
                        parentCommentId: Components.Schemas.CommentID(parentCommentServerId)
                    ),
                    initialBody: body
                )
            } else {
                presentComposer(
                    target: .postReply(serverPostId: viewModel.serverPostId),
                    initialBody: body
                )
            }
        }
    }
}
