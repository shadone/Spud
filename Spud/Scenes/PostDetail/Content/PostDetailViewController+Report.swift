//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// Reporting posts and comments to the moderators, hosted on
/// `PostDetailViewController`.
///
/// The entry points (`reportPost` / `reportComment`) are invoked from the
/// header/comment context and moderation menus in the main file. Each gates on
/// sign-in (via the shared `canReportOrPresentSignInAlert` on the `+Content`
/// seam), presents a reason prompt, and on confirm submits through the account's
/// `LemmyService`, confirming success or surfacing the error via `alertService`.
extension PostDetailViewController {
    // MARK: - Report

    func reportPost() {
        guard canReportOrPresentSignInAlert() else { return }
        presentReportReasonAlert(
            title: NSLocalizedString("Report post", comment: "Report post dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this post.", comment: "Report post dialog message")
        ) { [weak self] reason in
            Task { await self?.submitPostReport(reason: reason) }
        }
    }

    private func submitPostReport(reason: String) async {
        Haptics.tap()
        do {
            try await viewModel.reportPost(reason: reason)
            Haptics.success()
            presentReportSubmittedConfirmation()
        } catch {
            alertService.handle(error, for: .reportPost)
        }
    }

    func reportComment(serverCommentId: Int64) {
        guard canReportOrPresentSignInAlert() else { return }
        presentReportReasonAlert(
            title: NSLocalizedString("Report comment", comment: "Report comment dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this comment.", comment: "Report comment dialog message")
        ) { [weak self] reason in
            Task { await self?.submitCommentReport(serverCommentId: serverCommentId, reason: reason) }
        }
    }

    private func submitCommentReport(serverCommentId: Int64, reason: String) async {
        Haptics.tap()
        do {
            try await viewModel.reportComment(serverCommentId: serverCommentId, reason: reason)
            Haptics.success()
            presentReportSubmittedConfirmation()
        } catch {
            alertService.handle(error, for: .reportComment)
        }
    }
}
