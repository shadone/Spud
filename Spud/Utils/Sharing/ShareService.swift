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
    /// Presents the system share sheet for arbitrary `items` (e.g. a URL, or a
    /// share-as-image PNG file URL plus a permalink), anchoring the popover to
    /// `sourceItem` (preferred), then `sourceView`, then the view's center as a
    /// fallback on iPad.
    ///
    /// Deliberately does NOT fire a haptic: callers own their own feedback story
    /// (the ``presentShareSheet(for:sourceView:sourceItem:)`` convenience fires
    /// the light share haptic; the media viewer, which had none, keeps none).
    func presentShareSheet(
        items: [Any],
        sourceView: UIView? = nil,
        sourceItem: UIBarButtonItem? = nil
    ) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
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

    /// Presents the system share sheet for `url`, anchoring the popover to
    /// `sourceView` (or `sourceItem`) on iPad, and firing a light haptic.
    func presentShareSheet(
        for url: URL,
        sourceView: UIView? = nil,
        sourceItem: UIBarButtonItem? = nil
    ) {
        Haptics.tap()
        presentShareSheet(items: [url], sourceView: sourceView, sourceItem: sourceItem)
    }
}
