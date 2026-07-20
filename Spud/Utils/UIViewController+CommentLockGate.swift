//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

extension UIViewController {
    /// Presents the locked-post safety net at a composer choke point: a
    /// lightweight, dismissible alert explaining that new comments/replies are
    /// off, using `CommentLockPolicy`'s copy.
    ///
    /// Every reply affordance (overflow "Add comment", comment swipe/context-menu
    /// Reply, feed swipe/context-menu Reply) already omits itself when a post is
    /// locked — this is the backstop at `PostDetailViewController.presentComposer(target:)`
    /// / `PostListViewController.replyToPost(serverPostId:)` for any caller that
    /// reaches the composer anyway. Mirrors `presentSignInGate`'s pattern (warning
    /// haptic + a single dismissible alert), but with locked-post copy — not
    /// sign-in-specific wording or actions.
    func presentCommentLockedGate() {
        Haptics.warning()
        let alert = UIAlertController(
            title: CommentLockPolicy.title,
            message: CommentLockPolicy.message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Locked-post gate alert: dismiss button"),
            style: .default
        ))
        present(alert, animated: true)
    }
}
