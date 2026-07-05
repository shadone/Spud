//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// Shared post-action dispatch (vote / save) for every screen that shows a
/// post row (feed, person profile, activity). The save / vote paths go through
/// the SAME per-account optimistic `LemmyService` calls the feed uses (the
/// durable outbox), never a direct network write, so feed parity is structural
/// rather than copy-pasted.
///
/// Conformers supply the per-screen bits: the account scope, the alert service,
/// the current saved state for a post, and the sign-in gate presenter (every
/// conformer already has `presentSignInGate(title:)` via the `UIViewController`
/// extension).
///
/// Precedent: `InternalLinkRouting` (a protocol implemented per-VC with shared
/// default behavior).
@MainActor
protocol PostActionDispatching: UIViewController {
    var postActionsAccountScope: AccountScope { get }
    var postActionsAlertService: AlertServiceType { get }
    /// Currently observed saved state for the post (used by save-toggle).
    func currentSavedState(serverPostId: Int64) -> Bool
    func presentSignInGate(title: String)
}

@MainActor
extension PostActionDispatching {
    /// Votes on the post through the per-account optimistic outbox path (the
    /// same `lemmyService.vote` the feed calls): the local write applies
    /// synchronously and flows back through the row observation; network
    /// failures are retried by the outbox.
    func vote(serverPostId: Int64, action: VoteStatus.Action) async {
        guard !postActionsAccountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to vote", comment: "Sign-in gate title when a signed-out user tries to vote")
            )
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await postActionsAccountScope.lemmyService
                .vote(serverPostId: Components.Schemas.PostID(serverPostId), vote: action)
        } catch {
            // The optimistic write already applied synchronously inside enqueue;
            // network failures are retried by the outbox and surfaced via toast.
            // This catch is now a defensive log only.
            postActionsAlertService.handle(error, for: .vote)
        }
    }

    /// Toggles the saved state for `serverPostId` against its currently
    /// observed value, gating on sign-in. Routes through `lemmyService.setSaved`
    /// — the optimistic outbox path.
    func toggleSaved(serverPostId: Int64) {
        guard !postActionsAccountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to save", comment: "Sign-in gate title when a signed-out user tries to save a post")
            )
            return
        }
        let currentlySaved = currentSavedState(serverPostId: serverPostId)
        Task { await setSaved(serverPostId: serverPostId, saved: !currentlySaved) }
    }

    func setSaved(serverPostId: Int64, saved: Bool) async {
        Haptics.tap()
        do {
            try await postActionsAccountScope.lemmyService
                .setSaved(serverPostId: Components.Schemas.PostID(serverPostId), saved: saved)
        } catch {
            postActionsAlertService.handle(error, for: .save)
        }
    }
}
