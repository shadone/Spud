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

/// Cross-seam content helpers shared by `PostDetailViewController`'s post-level
/// and comment-level action paths and by its sibling `+Report` seam.
///
/// These are the members multiple seams reach for: the offline-action toast
/// trio (`showOfflineActionToastIfNeeded` + the `offlineVoteToast` /
/// `offlineSaveToast` copy), the save/report sign-in gates, and the own-content
/// check that hides "Report" on the user's own posts/comments. They live here,
/// not on any one action file, because both the vote/save handlers (still on the
/// main file) and the extracted `+Report` file call them.
extension PostDetailViewController {
    /// Shows a coalescing, non-blocking toast reassuring the user that an
    /// optimistic action (vote/save) will be sent once they're back online.
    /// No-op when online (the action goes out immediately) or when there is no
    /// window to present in. Relies on `ToastPresenter`'s plain-toast coalescing
    /// so rapid taps update the same pill instead of stacking.
    ///
    /// The optimistic DB write + the durable mutation outbox already record and
    /// resend the action; this toast only sets the user's expectation. No extra
    /// haptic is fired here — the calling action already plays its own.
    func showOfflineActionToastIfNeeded(message: String) {
        guard !reachabilityMonitor.isOnline, let window = view.window else { return }
        ToastPresenter.shared.show(message, in: window)
    }

    /// Toast copy for an optimistic vote queued while offline.
    static let offlineVoteToast = NSLocalizedString(
        "You're offline — we'll send your vote when you're back online.",
        comment: "Toast shown after voting while offline; the vote is queued and resent automatically"
    )

    /// Toast copy for an optimistic save/unsave queued while offline.
    static let offlineSaveToast = NSLocalizedString(
        "You're offline — we'll save this when you're back online.",
        comment: "Toast shown after saving while offline; the action is queued and resent automatically"
    )

    /// Whether the backing account can perform save actions. Signed-out
    /// accounts get a "Sign in to save" alert and a warning haptic.
    func canSaveOrPresentSignInAlert() -> Bool {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to save", comment: "Sign-in gate title when a signed-out user tries to save")
            )
            return false
        }
        return true
    }

    /// True when `creatorPersonId` matches the backing account's own person id.
    /// Reporting your own content is meaningless, so the "Report" action is
    /// hidden for it.
    func isOwnContent(creatorPersonId: Int64?) -> Bool {
        guard let creatorPersonId else { return false }
        guard let own = appDatabase.accountOwnPersonIdsSync(
            forKeychainId: viewModel.accountKeychainId
        ) else { return false }
        return creatorPersonId == own.serverPersonId
    }

    /// Whether the backing account can report content. Signed-out accounts get
    /// a "Sign in to report" alert and a warning haptic.
    func canReportOrPresentSignInAlert() -> Bool {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to report", comment: "Sign-in gate title when a signed-out user tries to report")
            )
            return false
        }
        return true
    }
}

// MARK: - PostSaveDispatching

/// Folds PostDetail's post-level vote/save into the shared post-action protocol
/// so the header cell, swipe, and overflow-menu affordances go through the same
/// optimistic-outbox dispatch the feed uses. PostDetail supplies the per-screen
/// bits and — via `postActionWillDispatch` — its offline-action toast, matching
/// the pre-fold `voteOnPost`/`setSavedOnPost` byte-for-byte (post-haptic,
/// pre-send). The COMMENT-level vote/save path stays on the main file and keeps
/// using `canSaveOrPresentSignInAlert` / `showOfflineActionToastIfNeeded`.
extension PostDetailViewController: PostSaveDispatching {
    var postActionsAccountScope: AccountScope {
        viewModel.accountScope
    }

    var postActionsAlertService: AlertServiceType {
        alertService
    }

    /// PostDetail shows exactly one post, so its saved state is the header row's
    /// (the `serverPostId` argument is always this post's id).
    func currentSavedState(serverPostId _: Int64) -> Bool {
        viewModel.headerRow?.isSaved ?? false
    }

    /// Post-haptic, pre-send offline reassurance toast — the exact toast the
    /// pre-fold `voteOnPost` / `setSavedOnPost` showed at this point.
    func postActionWillDispatch(_ action: PostActionKind) {
        switch action {
        case .vote:
            showOfflineActionToastIfNeeded(message: Self.offlineVoteToast)
        case .save:
            showOfflineActionToastIfNeeded(message: Self.offlineSaveToast)
        }
    }
}
