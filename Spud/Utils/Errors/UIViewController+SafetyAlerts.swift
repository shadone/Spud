//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

extension UIViewController {
    /// Presents a report alert with a required free-text reason field. The
    /// submit action stays disabled until the field is non-empty; `onSubmit`
    /// receives the trimmed reason. Used by the post and comment "Report"
    /// context-menu actions.
    func presentReportReasonAlert(
        title: String,
        message: String,
        onSubmit: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        let submitAction = UIAlertAction(
            title: NSLocalizedString("Report", comment: "Report alert submit button"),
            style: .destructive
        ) { [weak alert] _ in
            let reason = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !reason.isEmpty else { return }
            onSubmit(reason)
        }
        // Required field: keep submit disabled until the user types something.
        submitAction.isEnabled = false

        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString(
                "Reason (required)",
                comment: "Placeholder for the report reason text field"
            )
            textField.autocapitalizationType = .sentences
            textField.returnKeyType = .done
            textField.addAction(
                UIAction { [weak submitAction] _ in
                    let trimmed = textField.text?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    submitAction?.isEnabled = !trimmed.isEmpty
                },
                for: .editingChanged
            )
        }

        alert.addAction(submitAction)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel button"),
            style: .cancel
        ))

        present(alert, animated: true)
    }

    /// Presents a moderation alert with an optional free-text reason field
    /// (recorded in the mod log). Unlike `presentReportReasonAlert`, the reason
    /// is optional, so the submit action is always enabled; `onSubmit` receives
    /// the trimmed reason, or `nil` when left blank. The submit button uses a
    /// destructive style. Fires a warning haptic on show. Used by the post and
    /// comment "Remove" mod actions.
    func presentModerationReasonAlert(
        title: String,
        message: String,
        submitTitle: String,
        onSubmit: @escaping (String?) -> Void
    ) {
        Haptics.warning()
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        let submitAction = UIAlertAction(
            title: submitTitle,
            style: .destructive
        ) { [weak alert] _ in
            Haptics.success()
            let trimmed = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            onSubmit(trimmed.isEmpty ? nil : trimmed)
        }

        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString(
                "Reason (optional)",
                comment: "Placeholder for the moderation reason text field"
            )
            textField.autocapitalizationType = .sentences
            textField.returnKeyType = .done
        }

        alert.addAction(submitAction)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel button"),
            style: .cancel
        ))

        present(alert, animated: true)
    }

    /// Presents the ban-from-community confirmation as an action sheet offering
    /// "Ban" and "Ban and remove content" (or a single "Unban" when lifting a
    /// ban), then prompts for an optional reason. `onConfirm` receives whether
    /// to also remove the user's existing content and the trimmed reason.
    func presentBanFromCommunityConfirmation(
        userName: String,
        communityName: String,
        sourceView: UIView? = nil,
        onConfirm: @escaping (_ removeData: Bool, _ reason: String?) -> Void
    ) {
        Haptics.warning()
        let title = String(
            format: NSLocalizedString(
                "Ban %@ from %@?",
                comment: "Ban-from-community confirmation title; first arg user, second community"
            ),
            userName, communityName
        )
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

        let promptReason: (Bool) -> Void = { [weak self] removeData in
            self?.presentModerationReasonAlert(
                title: NSLocalizedString("Ban reason", comment: "Ban reason dialog title"),
                message: NSLocalizedString(
                    "Optionally tell the user why they're being banned.",
                    comment: "Ban reason dialog message"
                ),
                submitTitle: NSLocalizedString("Ban", comment: "Ban alert submit button")
            ) { reason in
                onConfirm(removeData, reason)
            }
        }

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Ban", comment: "Ban action"),
            style: .destructive
        ) { _ in promptReason(false) })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Ban and remove content", comment: "Ban-and-remove-data action"),
            style: .destructive
        ) { _ in promptReason(true) })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel button"),
            style: .cancel
        ))
        if let sourceView {
            alert.popoverPresentationController?.sourceView = sourceView
            alert.popoverPresentationController?.sourceRect = sourceView.bounds
        }
        present(alert, animated: true)
    }

    /// Presents a destructive confirmation action sheet (e.g. block user /
    /// block community). Fires a warning haptic on show and a success haptic
    /// when the user confirms. `sourceItem` anchors the sheet on iPad.
    func presentDestructiveConfirmation(
        title: String,
        message: String?,
        confirmTitle: String,
        sourceItem: UIBarButtonItem? = nil,
        sourceView: UIView? = nil,
        onConfirm: @escaping () -> Void
    ) {
        Haptics.warning()
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: confirmTitle,
            style: .destructive
        ) { _ in
            Haptics.success()
            onConfirm()
        })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel button"),
            style: .cancel
        ))
        if let sourceItem {
            alert.popoverPresentationController?.barButtonItem = sourceItem
        } else if let sourceView {
            alert.popoverPresentationController?.sourceView = sourceView
            alert.popoverPresentationController?.sourceRect = sourceView.bounds
        }
        present(alert, animated: true)
    }

    /// Presents a brief "report submitted" confirmation.
    func presentReportSubmittedConfirmation() {
        presentErrorAlert(
            title: NSLocalizedString("Report submitted", comment: "Report success alert title"),
            message: NSLocalizedString(
                "Thanks. The moderators will review it.",
                comment: "Report success alert body"
            )
        )
    }
}
