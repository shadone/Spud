//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit

/// Helpers for sharing posts and comments via `UIActivityViewController`.
///
/// The shared URL prefers the federation permalink (`ap_id`) carried on the
/// row; if that is empty it falls back to constructing
/// `<instance>/post/<id>` or `<instance>/comment/<id>` from the account's
/// home-instance actor id — mirroring the existing open-in-browser path.
enum ShareURL {
    /// The canonical URL for a post. Prefers `originalPostUrl` (the `ap_id`),
    /// else builds one from the home instance and the server post id.
    static func forPost(
        originalPostUrl: String?,
        serverPostId: Int64,
        instanceActorId: String?
    ) -> URL? {
        canonical(
            preferred: originalPostUrl,
            instanceActorId: instanceActorId,
            path: "post/\(serverPostId)"
        )
    }

    /// The canonical URL for a comment. Prefers `originalCommentUrl` (the
    /// `ap_id`), else builds one from the home instance and the server comment
    /// id.
    static func forComment(
        originalCommentUrl: String?,
        serverCommentId: Int64,
        instanceActorId: String?
    ) -> URL? {
        canonical(
            preferred: originalCommentUrl,
            instanceActorId: instanceActorId,
            path: "comment/\(serverCommentId)"
        )
    }

    private static func canonical(
        preferred: String?,
        instanceActorId: String?,
        path: String
    ) -> URL? {
        if
            let preferred,
            !preferred.isEmpty,
            let url = URL(string: preferred)
        {
            return url
        }
        guard
            let instanceActorId,
            let instanceUrl = URL(string: instanceActorId)
        else { return nil }
        return instanceUrl.appending(path: path)
    }
}

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
