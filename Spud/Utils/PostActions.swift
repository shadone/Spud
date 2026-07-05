//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// A post action that is about to dispatch through the optimistic outbox.
/// Used by the `postActionWillDispatch(_:)` hook so a screen can react
/// (e.g. show an offline-queued toast) just before the write.
enum PostActionKind {
    case vote
    case save
}

/// Shared post-action VOTE dispatch for every screen that shows a post row
/// (feed, person profile, activity). The vote path goes through the SAME
/// per-account optimistic `LemmyService` calls the feed uses (the durable
/// outbox), never a direct network write, so feed parity is structural rather
/// than copy-pasted.
///
/// Conformers supply the per-screen bits: the account scope and the alert
/// service. The sign-in gate (`presentSignInGate(title:)`) is intentionally NOT
/// a protocol requirement — the default impls below call it and it resolves via
/// the `UIViewController` extension in `UIViewController+SignInGate.swift`,
/// available to every conformer because these protocols refine `UIViewController`.
/// Declaring it as a requirement would risk witness-table shadowing (a conformer
/// silently supplying a different gate), so we lean on the shared extension.
///
/// Split rationale: vote-only screens (Activity) shouldn't have to stub a saved
/// state, so save lives in the refining `PostSaveDispatching`.
///
/// Precedent: `InternalLinkRouting` (a protocol implemented per-VC with shared
/// default behavior).
@MainActor
protocol PostVoteDispatching: UIViewController {
    var postActionsAccountScope: AccountScope { get }
    var postActionsAlertService: AlertServiceType { get }
    /// Called just before a vote/save dispatches while offline-queued behavior
    /// may apply. Default: no-op. PostDetail shows its offline-action toast here.
    func postActionWillDispatch(_ action: PostActionKind)
}

@MainActor
extension PostVoteDispatching {
    func postActionWillDispatch(_: PostActionKind) { }

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
        postActionWillDispatch(.vote)
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
}

/// Adds SAVE dispatch on top of `PostVoteDispatching` for screens that render a
/// post-save affordance (feed, person profile). Vote-only screens conform to
/// `PostVoteDispatching` alone and avoid stubbing a saved state they don't have.
///
/// Same outbox-parity guarantee as vote: `toggleSaved`/`setSaved` route through
/// `lemmyService.setSaved` (the optimistic outbox path), not a direct write.
@MainActor
protocol PostSaveDispatching: PostVoteDispatching {
    /// Currently observed saved state for the post (used by save-toggle).
    func currentSavedState(serverPostId: Int64) -> Bool
}

@MainActor
extension PostSaveDispatching {
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
        postActionWillDispatch(.save)
        do {
            try await postActionsAccountScope.lemmyService
                .setSaved(serverPostId: Components.Schemas.PostID(serverPostId), saved: saved)
        } catch {
            postActionsAlertService.handle(error, for: .save)
        }
    }
}
