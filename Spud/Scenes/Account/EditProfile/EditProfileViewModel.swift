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
/// own `PersonRecord` / `AccountRecord` (read synchronously at bring-up) and
/// pushes the edit to the server via `LemmyService.saveProfile`. A picked avatar
/// or banner is previewed locally from the picked image (no pick-time upload) and
/// uploaded exactly once, at save.
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

    /// The locally-picked avatar image, shown in the editor preview the instant
    /// the user picks it — no network round-trip. Nil until a pick (and cleared by
    /// Remove Photo); while nil the existing remote ``avatarUrl`` drives the
    /// preview. The bytes behind it upload exactly once, in ``save()``. Held on the
    /// `@MainActor` VM so the non-`Sendable` `UIImage` never crosses an actor
    /// boundary — only `Data` reaches `LemmyService`.
    private(set) var pickedAvatarImage: UIImage?
    /// The banner twin of ``pickedAvatarImage``.
    private(set) var pickedBannerImage: UIImage?

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

    /// Save is blocked only while a save is already in flight. Picking an avatar or
    /// banner no longer performs a pick-time upload, so there is no per-image
    /// in-flight state to gate on — the single upload happens inside ``save()``.
    var canSave: Bool {
        !isSaving
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

    /// Records a picked avatar for preview and save. Decodes the picked bytes,
    /// re-encodes to JPEG (quality 0.85, matching the New Post composer), and
    /// retains both the encoded bytes (for the single save-time upload via
    /// `setAvatarNeutral`) and the decoded image (for the instant local preview via
    /// ``pickedAvatarImage``). Does NOT upload — the avatar reaches the server only
    /// in ``save()``, so a pick no longer performs a throwaway upload that orphaned
    /// a pict-rs file every time. Un-decodable data is ignored.
    func pickAvatar(imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        pickedAvatarImage = image
        pendingAvatarData = image.jpegData(compressionQuality: 0.85) ?? imageData
        pendingAvatarFileName = "avatar-\(UUID().uuidString).jpg"
        avatarEdited = true
    }

    /// Clears the avatar. On save the removal is pushed to the server via
    /// `removeAvatarNeutral`.
    func removeAvatar() {
        avatarUrl = nil
        pickedAvatarImage = nil
        avatarEdited = true
        pendingAvatarData = nil
        pendingAvatarFileName = nil
    }

    // MARK: Banner

    /// Records a picked banner for preview and save — the banner twin of
    /// ``pickAvatar(imageData:)``. Decodes and re-encodes to JPEG (quality 0.85),
    /// retaining the bytes for the single save-time upload and the decoded image
    /// for the instant local preview (``pickedBannerImage``). Does NOT upload; the
    /// banner reaches the server only in ``save()``.
    func pickBanner(imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        pickedBannerImage = image
        pendingBannerData = image.jpegData(compressionQuality: 0.85) ?? imageData
        pendingBannerFileName = "banner-\(UUID().uuidString).jpg"
        bannerEdited = true
    }

    /// Clears the banner. On save the removal is pushed to the server via
    /// `removeBannerNeutral`.
    func removeBanner() {
        bannerUrl = nil
        pickedBannerImage = nil
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
