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
    /// Start (or continue) a private message conversation with `recipientId`.
    case privateMessage(recipientId: Components.Schemas.PersonID)
    /// Compose a brand-new post. `serverCommunityId` may be pre-filled when the
    /// flow is entered from a community screen. The title/url/image/nsfw surface
    /// for this case lives in `NewPostViewController`, not the comment composer.
    case newPost(serverCommunityId: Components.Schemas.CommunityID?, initialCommunityName: String?)
    /// Edit the user's own existing comment. The editor is seeded with the
    /// comment's current body and the saved edit is enqueued to the content
    /// outbox (the performer calls `editComment`).
    case editComment(serverPostId: Components.Schemas.PostID, serverCommentId: Components.Schemas.CommentID)

    var serverPostId: Components.Schemas.PostID? {
        switch self {
        case let .commentReply(serverPostId, _): serverPostId
        case let .postReply(serverPostId): serverPostId
        case let .editComment(serverPostId, _): serverPostId
        case .privateMessage, .newPost: nil
        }
    }

    var parentCommentId: Components.Schemas.CommentID? {
        switch self {
        case let .commentReply(_, parentCommentId): parentCommentId
        case .postReply, .privateMessage, .newPost, .editComment: nil
        }
    }

    /// The server id of the comment being edited, or nil for create flows.
    var editCommentServerId: Components.Schemas.CommentID? {
        switch self {
        case let .editComment(_, serverCommentId): serverCommentId
        case .commentReply, .postReply, .privateMessage, .newPost: nil
        }
    }

    var privateMessageRecipientId: Components.Schemas.PersonID? {
        switch self {
        case let .privateMessage(recipientId): recipientId
        case .commentReply, .postReply, .newPost, .editComment: nil
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
    private let accountScope: AccountScope

    /// Optional text to seed the editor with when there is no saved draft (used
    /// by the failed-comment Edit flow so the user's text isn't lost). Cleared
    /// once applied so a later draft load doesn't fight it.
    @ObservationIgnored
    private var initialBody: String?

    /// For `.editComment`, the comment's body when the editor opened. The Save
    /// button stays disabled until the text differs from this, so an unchanged
    /// edit can't be enqueued. nil for create flows (no change gate).
    @ObservationIgnored
    private var originalBody: String?

    var bodyText: String = ""
    var submissionState: ComposerSubmissionState = .editing

    /// The Post/Save button is enabled only when there is non-whitespace content
    /// and we are not mid-submission. For an edit it must additionally have
    /// changed from the original body.
    var canPost: Bool {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, submissionState != .submitting else { return false }
        if let originalBody {
            return trimmed != originalBody.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return true
    }

    var isSubmitting: Bool {
        submissionState == .submitting
    }

    var navigationTitle: String {
        switch target {
        case .commentReply: NSLocalizedString("Reply", comment: "Composer title when replying to a comment")
        case .postReply: NSLocalizedString("Add comment", comment: "Composer title when replying to a post")
        case .privateMessage: NSLocalizedString("New message", comment: "Composer title when composing a private message")
        case .newPost: NSLocalizedString("New post", comment: "Composer title when composing a new post")
        case .editComment: NSLocalizedString("Edit comment", comment: "Composer title when editing the user's own comment")
        }
    }

    /// The submit-button title — "Save" when editing, "Post" otherwise.
    var submitButtonTitle: String {
        switch target {
        case .editComment: NSLocalizedString("Save", comment: "Composer submit button when editing a comment")
        case .commentReply, .postReply, .privateMessage, .newPost:
            NSLocalizedString("Post", comment: "Composer submit button")
        }
    }

    @ObservationIgnored private var clientToken: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private var draftKey: String? {
        if let editCommentServerId = target.editCommentServerId {
            return OutboundContentRecord.editCommentDraftKey(serverCommentId: Int64(editCommentServerId))
        }
        guard let postId = target.serverPostId else { return nil }
        return OutboundContentRecord.commentDraftKey(
            postServerId: Int64(postId),
            parentCommentServerId: target.parentCommentId.map { Int64($0) }
        )
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(
        target: ComposerTarget,
        accountScope: AccountScope,
        initialBody: String? = nil,
        dependencies: Dependencies
    ) {
        self.target = target
        self.accountScope = accountScope
        self.initialBody = initialBody
        self.dependencies = dependencies
    }

    func loadExistingDraft() async {
        // For an edit, the caller passes the comment's current body as
        // `initialBody`. Record it as the change baseline so an unchanged edit
        // can't be saved, regardless of whether a saved edit draft is loaded.
        if target.editCommentServerId != nil {
            originalBody = initialBody
        }

        if let draftKey,
           let row = try? await accountScope.lemmyService.loadDraft(draftKey: draftKey),
           !row.body.isEmpty
        {
            clientToken = row.clientToken
            bodyText = row.body
        } else if let initialBody, !initialBody.isEmpty {
            // No saved draft: seed the editor with the caller-provided text (e.g.
            // a failed comment being edited, or the comment's current body when
            // editing) so it isn't lost.
            bodyText = initialBody
        }
        initialBody = nil
    }

    func bodyDidChange() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await self?.flushDraft()
        }
    }

    func flushDraft() async {
        guard let postId = target.serverPostId else { return }
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let input = OutboundDraftInput(
            kind: .comment, body: bodyText, postServerId: Int64(postId),
            parentCommentServerId: target.parentCommentId.map { Int64($0) },
            communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0,
            editCommentServerId: target.editCommentServerId.map { Int64($0) }
        )
        clientToken = try? await accountScope.lemmyService.saveDraft(input)
    }

    func discardDraft() async {
        if let token = clientToken {
            await accountScope.lemmyService.discardComposition(clientToken: token)
            clientToken = nil
        }
    }

    func post() async {
        let content = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard submissionState == .editing else { return }
        submissionState = .submitting

        if target.serverPostId != nil {
            // Comment/post-reply: save to outbox and enqueue optimistically.
            await flushDraft()
            guard let token = clientToken else {
                submissionState = .failed(message: NSLocalizedString("Couldn't save your comment.", comment: "Composer enqueue failure"))
                return
            }
            await accountScope.lemmyService.submitDraft(clientToken: token)
            clientToken = nil
            submissionState = .finished
        } else {
            // DM / new-post: existing blocking network flow.
            let service = accountScope.lemmyService
            do {
                if let recipientId = target.privateMessageRecipientId {
                    try await service.sendPrivateMessage(content: content, recipientId: recipientId)
                }
                submissionState = .finished
            } catch {
                alertService.handle(error, for: .sendPrivateMessage)
                submissionState = .failed(message: ErrorMessage.userFacing(for: error))
            }
        }
    }

    /// Called by the view controller after it has presented the failure
    /// alert, so a subsequent retry starts from a clean editing state.
    func didPresentFailure() {
        submissionState = .editing
    }
}
