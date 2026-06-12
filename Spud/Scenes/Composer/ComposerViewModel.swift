//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// Identifies what a composed comment is replying to. Reused later for
/// post/edit/DM composition by adding cases here.
enum ComposerTarget {
    /// Reply to a comment on the given post.
    case commentReply(serverPostId: Components.Schemas.PostID, parentCommentId: Components.Schemas.CommentID)
    /// Reply to the post itself (a top-level comment).
    case postReply(serverPostId: Components.Schemas.PostID)

    var serverPostId: Components.Schemas.PostID {
        switch self {
        case let .commentReply(serverPostId, _): serverPostId
        case let .postReply(serverPostId): serverPostId
        }
    }

    var parentCommentId: Components.Schemas.CommentID? {
        switch self {
        case let .commentReply(_, parentCommentId): parentCommentId
        case .postReply: nil
        }
    }
}

/// The outcome of submitting a composed comment, surfaced to the view
/// controller via `ObservationStream`.
enum ComposerSubmissionState: Equatable {
    case editing
    case submitting
    /// Submission succeeded; the view controller should dismiss. The thread's
    /// GRDB observation refreshes the new comment in.
    case finished
    /// Submission failed; the view controller should present `error` and keep
    /// the draft so the user can retry.
    case failed(message: String)
}

@MainActor
@Observable
final class ComposerViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    private let target: ComposerTarget

    @ObservationIgnored
    let accountKeychainId: String

    var bodyText: String = ""
    var submissionState: ComposerSubmissionState = .editing

    /// The Post button is enabled only when there is non-whitespace content
    /// and we are not mid-submission.
    var canPost: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && submissionState != .submitting
    }

    var isSubmitting: Bool {
        submissionState == .submitting
    }

    var navigationTitle: String {
        switch target {
        case .commentReply: NSLocalizedString("Reply", comment: "Composer title when replying to a comment")
        case .postReply: NSLocalizedString("Add comment", comment: "Composer title when replying to a post")
        }
    }

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(
        target: ComposerTarget,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.target = target
        self.accountKeychainId = accountKeychainId
        self.dependencies = dependencies
    }

    func post() async {
        let content = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        submissionState = .submitting
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: accountKeychainId)
                .createComment(
                    serverPostId: target.serverPostId,
                    content: content,
                    parentCommentId: target.parentCommentId
                )
            submissionState = .finished
        } catch {
            // Keep the existing logging behaviour, then surface to the user.
            alertService.handle(error, for: .createComment)
            submissionState = .failed(message: ErrorMessage.userFacing(for: error))
        }
    }

    /// Called by the view controller after it has presented the failure
    /// alert, so a subsequent retry starts from a clean editing state.
    func didPresentFailure() {
        submissionState = .editing
    }
}
