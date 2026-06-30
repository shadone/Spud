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
import UIKit

private let logger = Logger.app

/// Drives the Edit Profile editor. Seeds its editable fields from the account's
/// own `PersonRecord` / `AccountRecord` (read synchronously at bring-up), pushes
/// the edit to the server via `LemmyService.saveProfile`, and handles avatar
/// changes (pick -> JPEG -> upload) against the same account's `LemmyService`.
@MainActor
@Observable
final class EditProfileViewModel {
    // MARK: Editable fields

    var displayName: String
    var bio: String
    /// The current avatar URL (remote), nil when none. Updated after an upload
    /// or cleared by "Remove Photo".
    private(set) var avatarUrl: URL?
    /// The account's read-only username, shown as context in the editor header.
    let name: String

    var showScores: Bool
    var showBotAccounts: Bool
    var showReadPosts: Bool
    var showAvatars: Bool
    var defaultListingType: Components.Schemas.ListingType

    // MARK: Status

    enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    private(set) var saveState: SaveState = .idle
    /// True while an avatar upload is in flight (drives the avatar spinner and
    /// disables Save so a half-uploaded avatar can't be committed).
    private(set) var isUploadingAvatar = false

    /// Emits once the save completed successfully so the host can dismiss.
    @ObservationIgnored
    private var onSaved: (() -> Void)?

    // MARK: Dependencies

    @ObservationIgnored
    private let accountScope: AccountScope
    @ObservationIgnored
    private let appDatabase: AppDatabase
    @ObservationIgnored
    private let accountService: AccountServiceType

    // MARK: Init

    init(
        accountScope: AccountScope,
        appDatabase: AppDatabase,
        accountService: AccountServiceType,
        onSaved: @escaping () -> Void
    ) {
        self.accountScope = accountScope
        self.appDatabase = appDatabase
        self.accountService = accountService
        self.onSaved = onSaved

        let profile = appDatabase.accountEditableProfileSync(
            forKeychainId: accountScope.accountKeychainId
        )

        displayName = profile?.displayName ?? ""
        bio = profile?.bio ?? ""
        avatarUrl = profile?.avatarUrl.flatMap { URL(string: $0) }
        name = profile?.name ?? ""
        showScores = profile?.showScores ?? true
        showBotAccounts = profile?.showBotAccounts ?? true
        showReadPosts = profile?.showReadPosts ?? true
        showAvatars = profile?.showAvatars ?? true
        defaultListingType = profile?.defaultListingType ?? .All
    }

    // MARK: Derived

    var isSaving: Bool {
        saveState == .saving
    }

    /// Save is blocked while a save or an avatar upload is already in flight.
    var canSave: Bool {
        !isSaving && !isUploadingAvatar
    }

    /// Whether the avatar was changed in this session (set or removed). Tracked so
    /// `saveProfile` only sends the `avatar` field when the user actually touched
    /// it (passing `nil` otherwise leaves the server value unchanged).
    @ObservationIgnored
    private var avatarEdited = false

    // MARK: Avatar

    /// Uploads picked image data as the account's new avatar. Encodes to JPEG
    /// (quality 0.85, matching the New Post composer) and uploads via the
    /// account's `LemmyService`, then points `avatarUrl` at the uploaded image.
    func uploadAvatar(imageData: Data) async {
        guard let image = UIImage(data: imageData) else { return }
        let jpegData = image.jpegData(compressionQuality: 0.85) ?? imageData
        let fileName = "avatar-\(UUID().uuidString).jpg"

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            let url = try await accountScope.lemmyService.uploadImage(
                imageData: jpegData,
                fileName: fileName,
                mimeType: "image/jpeg"
            )
            avatarUrl = url
            avatarEdited = true
        } catch {
            logger.error("Avatar upload failed: \(String(describing: error), privacy: .public)")
            saveState = .failed(NSLocalizedString(
                "Couldn't upload the photo. Please try again.",
                comment: "Edit Profile avatar upload error"
            ))
        }
    }

    /// Clears the avatar. The empty string is sent to the server on save, which
    /// removes the avatar there too.
    func removeAvatar() {
        avatarUrl = nil
        avatarEdited = true
    }

    // MARK: Save

    /// Pushes the edited profile to the server, then signals the host to dismiss
    /// on success. On failure, parks an error message and stays open.
    func save() async {
        guard canSave else { return }
        saveState = .saving

        // Only send the avatar field when it was actually changed; passing nil
        // leaves the server's avatar untouched. A removed avatar is sent as "".
        let avatarToSend: String? = avatarEdited
            ? (avatarUrl?.absoluteString ?? "")
            : nil

        do {
            try await accountScope.lemmyService.saveProfile(
                displayName: displayName,
                bio: bio,
                avatar: avatarToSend,
                banner: nil, // TODO: Task 4 will wire the banner field from the editor
                showScores: showScores,
                showBotAccounts: showBotAccounts,
                showReadPosts: showReadPosts,
                showAvatars: showAvatars,
                defaultListingType: defaultListingType
            )
            saveState = .idle
            onSaved?()
        } catch {
            logger.error("Save profile failed: \(String(describing: error), privacy: .public)")
            saveState = .failed(NSLocalizedString(
                "Couldn't save your profile. Please check your connection and try again.",
                comment: "Edit Profile save error"
            ))
        }
    }

    /// Clears a parked error so the alert dismisses and the form is editable
    /// again.
    func clearError() {
        if case .failed = saveState {
            saveState = .idle
        }
    }
}
