//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// Helper for presenting the system share sheet for posts and comments.
/// URL construction lives in `LinkURL`.
extension UIViewController {
    /// Presents the system share sheet for `url`, anchoring the popover to
    /// `sourceView` (or `sourceItem`) on iPad, and firing a light haptic.
    func presentShareSheet(
        for url: URL,
        sourceView: UIView? = nil,
        sourceItem: UIBarButtonItem? = nil
    ) {
        Haptics.tap()
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let sourceItem {
            activityVC.popoverPresentationController?.barButtonItem = sourceItem
        } else if let sourceView {
            activityVC.popoverPresentationController?.sourceView = sourceView
            activityVC.popoverPresentationController?.sourceRect = sourceView.bounds
        } else {
            activityVC.popoverPresentationController?.sourceView = view
            activityVC.popoverPresentationController?.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 0,
                height: 0
            )
        }
        present(activityVC, animated: true)
    }
}
