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
