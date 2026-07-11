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
    /// The current banner URL (remote), nil when none. Updated after an upload
    /// or cleared by "Remove Banner".
    private(set) var bannerUrl: URL?
    /// The account's read-only username, shown as context in the editor header.
    let name: String

    var showScores: Bool
    var showBotAccounts: Bool
    var showReadPosts: Bool
    var showAvatars: Bool
    var defaultListingType: Lemmy.ListingType

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
    /// True while a banner upload is in flight (disables Save so a half-uploaded
    /// banner can't be committed).
    private(set) var isUploadingBanner = false

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
        bannerUrl = profile?.bannerUrl.flatMap { URL(string: $0) }
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

    /// Save is blocked while a save, an avatar upload, or a banner upload is
    /// already in flight.
    var canSave: Bool {
        !isSaving && !isUploadingAvatar && !isUploadingBanner
    }

    /// Whether the avatar was changed in this session (set or removed). Tracked so
    /// `saveProfile` only touches the avatar when the user actually edited it
    /// (`.unchanged` otherwise leaves the server value alone).
    @ObservationIgnored
    private var avatarEdited = false

    /// Whether the banner was changed in this session (set or removed). Mirrors
    /// `avatarEdited` — `saveProfile` only touches the banner when truly edited.
    @ObservationIgnored
    private var bannerEdited = false

    /// The raw JPEG bytes (and upload filename) of the most recently picked
    /// avatar, retained so `save()` can push them to the server via
    /// `setAvatarNeutral`. Nil when the avatar was removed (or never set) — a
    /// removal is `avatarEdited == true` with no pending bytes.
    @ObservationIgnored
    private var pendingAvatarData: Data?
    @ObservationIgnored
    private var pendingAvatarFileName: String?

    /// The banner twin of `pendingAvatarData` / `pendingAvatarFileName`.
    @ObservationIgnored
    private var pendingBannerData: Data?
    @ObservationIgnored
    private var pendingBannerFileName: String?

    // MARK: Avatar

    /// Uploads picked image data as the account's new avatar. Encodes to JPEG
    /// (quality 0.85, matching the New Post composer) and uploads via the
    /// account's `LemmyService`, then points `avatarUrl` at the uploaded image for
    /// the live preview. The encoded bytes are retained so `save()` can durably
    /// push the avatar to the server (the upload here only produces the preview
    /// url; the account's avatar isn't changed server-side until save).
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
            pendingAvatarData = jpegData
            pendingAvatarFileName = fileName
        } catch {
            logger.error("Avatar upload failed: \(String(describing: error), privacy: .public)")
            saveState = .failed(NSLocalizedString(
                "Couldn't upload the photo. Please try again.",
                comment: "Edit Profile avatar upload error"
            ))
        }
    }

    /// Clears the avatar. On save the removal is pushed to the server via
    /// `removeAvatarNeutral`.
    func removeAvatar() {
        avatarUrl = nil
        avatarEdited = true
        pendingAvatarData = nil
        pendingAvatarFileName = nil
    }

    // MARK: Banner

    /// Uploads picked image data as the account's new banner. Encodes to JPEG
    /// (quality 0.85, matching the avatar upload) and uploads via the account's
    /// `LemmyService`, then points `bannerUrl` at the uploaded image for the live
    /// preview. The encoded bytes are retained so `save()` can durably push the
    /// banner to the server.
    func uploadBanner(imageData: Data) async {
        guard let image = UIImage(data: imageData) else { return }
        let jpegData = image.jpegData(compressionQuality: 0.85) ?? imageData
        let fileName = "banner-\(UUID().uuidString).jpg"

        isUploadingBanner = true
        defer { isUploadingBanner = false }

        do {
            let url = try await accountScope.lemmyService.uploadImage(
                imageData: jpegData,
                fileName: fileName,
                mimeType: "image/jpeg"
            )
            bannerUrl = url
            bannerEdited = true
            pendingBannerData = jpegData
            pendingBannerFileName = fileName
        } catch {
            logger.error("Banner upload failed: \(String(describing: error), privacy: .public)")
            saveState = .failed(NSLocalizedString(
                "Couldn't upload the banner. Please try again.",
                comment: "Edit Profile banner upload error"
            ))
        }
    }

    /// Clears the banner. On save the removal is pushed to the server via
    /// `removeBannerNeutral`.
    func removeBanner() {
        bannerUrl = nil
        bannerEdited = true
        pendingBannerData = nil
        pendingBannerFileName = nil
    }

    // MARK: Save

    /// Pushes the edited profile to the server, then signals the host to dismiss
    /// on success. On failure, parks an error message and stays open.
    func save() async {
        guard canSave else { return }
        saveState = .saving

        // Only touch the avatar/banner when actually changed: `.unchanged` leaves
        // the server value alone, `.set` pushes the retained bytes, `.removed`
        // clears it. `canSave` already gated out an in-flight upload, so the
        // pending bytes are settled by now.
        let avatarEdit = Self.imageEdit(
            edited: avatarEdited,
            data: pendingAvatarData,
            fileName: pendingAvatarFileName
        )
        let bannerEdit = Self.imageEdit(
            edited: bannerEdited,
            data: pendingBannerData,
            fileName: pendingBannerFileName
        )

        do {
            try await accountScope.lemmyService.saveProfile(
                displayName: displayName,
                bio: bio,
                avatar: avatarEdit,
                banner: bannerEdit,
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

    /// Builds the `ProfileImageEdit` for a save from the tracked edit state: an
    /// untouched image is `.unchanged`; a touched image with retained bytes is
    /// `.set` (JPEG, so a fixed `image/jpeg` MIME); a touched image with no bytes
    /// is a `.removed`.
    private static func imageEdit(edited: Bool, data: Data?, fileName: String?) -> ProfileImageEdit {
        guard edited else { return .unchanged }
        guard let data else { return .removed }
        return .set(
            imageData: data,
            fileName: fileName ?? "image.jpg",
            contentType: "image/jpeg"
        )
    }

    /// Clears a parked error so the alert dismisses and the form is editable
    /// again.
    func clearError() {
        if case .failed = saveState {
            saveState = .idle
        }
    }
}
