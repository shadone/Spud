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

/// A community the user can post to, surfaced by the community picker.
struct NewPostCommunity: Equatable {
    let id: Components.Schemas.CommunityID
    /// Display name, e.g. `worldnews@lemmy.world` for a remote community or
    /// `gnome` for a local one.
    let qualifiedName: String
    let title: String
}

/// Which kind of post the user is composing. Mirrors Apollo's text/link/image
/// affordance: it only drives which input is emphasised — the underlying
/// `CreatePost` request is the same shape regardless.
enum NewPostType: Int, CaseIterable {
    case text
    case link
    case image
}

/// Outcome of submitting a new post, surfaced to the view controller via
/// `ObservationStream`.
enum NewPostSubmissionState: Equatable {
    case editing
    case uploadingImage
    case submitting
    /// Submission succeeded; carries the new post's server id so the view
    /// controller can dismiss and navigate to it.
    case finished(serverPostId: Components.Schemas.PostID)
    /// Submission failed; the view controller presents `message` and keeps the
    /// draft so the user can retry.
    case failed(message: String)
}

@MainActor
@Observable
final class NewPostViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    private let accountScope: AccountScope

    var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    // MARK: Draft state (draft-safe: never cleared on error or dismiss)

    var titleText: String = ""
    var bodyText: String = ""
    var urlText: String = ""
    var nsfw: Bool = false
    var postType: NewPostType = .text

    /// The selected target community. `nil` until the user picks one (or it was
    /// pre-filled from a community screen).
    var community: NewPostCommunity?

    var submissionState: NewPostSubmissionState = .editing

    /// Set while a pict-rs upload is in flight so the UI can show progress.
    var isUploadingImage: Bool = false

    // MARK: Derived UI state

    /// The Post button is enabled only with a non-empty title, a chosen
    /// community, and no in-flight work.
    var canPost: Bool {
        !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && community != nil
            && submissionState == .editing
    }

    var isBusy: Bool {
        switch submissionState {
        case .uploadingImage, .submitting: true
        case .editing, .finished, .failed: false
        }
    }

    var communityButtonTitle: String {
        community?.qualifiedName
            ?? NSLocalizedString("Choose a community", comment: "Placeholder on the new-post community picker button")
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(
        serverCommunityId: Components.Schemas.CommunityID?,
        initialCommunityName: String?,
        accountScope: AccountScope,
        dependencies: Dependencies
    ) {
        self.accountScope = accountScope
        self.dependencies = dependencies

        if let serverCommunityId {
            community = NewPostCommunity(
                id: serverCommunityId,
                qualifiedName: initialCommunityName ?? "",
                title: initialCommunityName ?? ""
            )
        }
    }

    // MARK: Image upload

    /// Uploads `imageData` to pict-rs and, on success, inserts the returned url
    /// into the post. For a `.image`/`.link` post it becomes the post url; for a
    /// `.text` post it is appended into the markdown body as an inline image.
    func uploadImage(imageData: Data, fileName: String) async {
        isUploadingImage = true
        submissionState = .uploadingImage
        defer { isUploadingImage = false }

        let service = accountScope.lemmyService
        do {
            let url = try await service.uploadImage(
                imageData: imageData,
                fileName: fileName,
                mimeType: "image/jpeg"
            )
            insertUploadedImageUrl(url)
            submissionState = .editing
        } catch {
            alertService.handle(error, for: .uploadImage)
            submissionState = .failed(message: ErrorMessage.userFacing(for: error))
        }
    }

    private func insertUploadedImageUrl(_ url: URL) {
        switch postType {
        case .image, .link:
            urlText = url.absoluteString
        case .text:
            let markdown = "![](\(url.absoluteString))"
            if bodyText.isEmpty {
                bodyText = markdown
            } else {
                bodyText += "\n\n" + markdown
            }
        }
    }

    // MARK: Submit

    func submit() async {
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let community else { return }

        submissionState = .submitting

        let trimmedUrl = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        let service = accountScope.lemmyService
        do {
            let serverPostId = try await service.createPost(
                serverCommunityId: community.id,
                name: title,
                url: trimmedUrl.isEmpty ? nil : trimmedUrl,
                body: trimmedBody.isEmpty ? nil : trimmedBody,
                nsfw: nsfw
            )
            submissionState = .finished(serverPostId: serverPostId)
        } catch {
            alertService.handle(error, for: .createPost)
            submissionState = .failed(message: ErrorMessage.userFacing(for: error))
        }
    }

    /// Called by the view controller after presenting the failure alert so a
    /// retry starts from a clean editing state (draft text preserved).
    func didPresentFailure() {
        submissionState = .editing
    }
}
