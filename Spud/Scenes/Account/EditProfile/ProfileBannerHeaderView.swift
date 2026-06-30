//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import PhotosUI
import SpudDataKit
import SwiftUI
import UIKit

/// A reusable banner + avatar header that supports two modes:
///
/// **Display-only** — pass `nil` for all `onPick*` / `onRemove*` arguments
/// (the Task 6 Account tab reuses it this way). No overlay buttons appear;
/// the images are rendered read-only.
///
/// **Interactive (editor)** — supply `onPickBanner`, `onPickAvatar`, and the
/// `onRemove*` callbacks. A camera-badge overlay on each element and "Remove"
/// destructive buttons in a context menu become active. The banner also exposes
/// VoiceOver actions for accessibility.
///
/// ## Layout
/// - Banner: full-width, `aspectFill`-clipped, ≈100 pt tall.
/// - Avatar: 72 pt circle, leading-aligned, overlapping the banner's bottom
///   edge by half its diameter (matching ``PersonHeaderView``).
/// - Loading spinners appear on whichever element is currently uploading.
struct ProfileBannerHeaderView: View {
    // MARK: Images

    /// The current banner image URL (nil → placeholder background fill).
    let bannerUrl: URL?
    /// The current avatar URL (nil → hue-tile fallback via ``ProfileAvatarView``).
    let avatarUrl: URL?
    /// The person's username; drives the hue and initial in the avatar fallback.
    let name: String

    // MARK: Upload state

    /// True while a banner upload is in flight; shows a spinner over the banner.
    let isUploadingBanner: Bool
    /// True while an avatar upload is in flight; shows a spinner over the avatar.
    let isUploadingAvatar: Bool

    // MARK: Interactive affordances (nil = display-only)

    /// Called with raw `Data` from the Photos picker when the user picks a new
    /// banner image. Pass `nil` to render the banner display-only (no picker).
    let onPickBanner: ((Data) async -> Void)?
    /// Called with raw `Data` when the user picks a new avatar image. Pass `nil`
    /// for display-only.
    let onPickAvatar: ((Data) async -> Void)?
    /// Called when the user removes the banner via the context menu. `nil` hides
    /// the remove affordance.
    let onRemoveBanner: (() -> Void)?
    /// Called when the user removes the avatar. `nil` hides the remove affordance.
    let onRemoveAvatar: (() -> Void)?

    // MARK: Internal picker state

    @State private var pickedBannerItem: PhotosPickerItem?
    @State private var pickedAvatarItem: PhotosPickerItem?

    // MARK: Environment

    /// Used to cap the banner width on iPad (regular size class).
    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: Constants (match PersonHeaderView)

    private let bannerHeight: CGFloat = 100
    private let avatarSize: CGFloat = 72
    /// How far the avatar overlaps below the banner's bottom edge.
    private var avatarOverlap: CGFloat {
        avatarSize / 2
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Banner + its interactive layer
            bannerContent
                .frame(height: bannerHeight + avatarOverlap)
                .clipped() // keep the spinner in-bounds; the banner itself clips inside

            // Avatar sits at the leading edge, its centre on the banner bottom
            avatarContent
                .padding(.leading, 16)
        }
        // Reserve bottom space for the avatar half that hangs below the banner
        .padding(.bottom, avatarOverlap)
        // On iPad (regular horizontal size class) centre the banner within a
        // capped column so it does not stretch full-bleed across the wide canvas.
        // Compact (iPhone) stays full-width (.infinity).
        .frame(maxWidth: hSizeClass == .regular ? AdaptiveLayout.contentMaxWidth : .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
        // Decode picked banner data and forward to the callback
        .onChange(of: pickedBannerItem) { _, newItem in
            guard let newItem, let onPickBanner else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await onPickBanner(data)
                }
                pickedBannerItem = nil
            }
        }
        // Decode picked avatar data and forward to the callback
        .onChange(of: pickedAvatarItem) { _, newItem in
            guard let newItem, let onPickAvatar else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await onPickAvatar(data)
                }
                pickedAvatarItem = nil
            }
        }
    }

    // MARK: Banner subview

    @ViewBuilder
    private var bannerContent: some View {
        if let onPickBanner {
            // Interactive: wrap in a PhotosPicker with context-menu "Remove"
            PhotosPicker(
                selection: $pickedBannerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                bannerImage
                    .overlay(alignment: .bottomTrailing) {
                        editBadge
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isUploadingBanner)
            .accessibilityLabel(Text(NSLocalizedString(
                "Profile banner",
                comment: "Edit Profile: banner accessibility label"
            )))
            .accessibilityHint(Text(NSLocalizedString(
                "Double-tap to change",
                comment: "Edit Profile: banner accessibility hint"
            )))
            .accessibilityAction(named: Text(NSLocalizedString(
                "Change banner",
                comment: "Edit Profile: banner VoiceOver action"
            ))) {
                // PhotosPicker is activated by its button; hint is sufficient
            }
            .contextMenu {
                if bannerUrl != nil, let onRemoveBanner {
                    Button(role: .destructive) {
                        onRemoveBanner()
                    } label: {
                        Label(
                            NSLocalizedString("Remove Banner", comment: "Edit Profile: remove banner context menu item"),
                            systemImage: "trash"
                        )
                    }
                }
            }
        } else {
            // Display-only
            bannerImage
                .accessibilityLabel(Text(NSLocalizedString(
                    "Profile banner",
                    comment: "Profile header: banner accessibility label"
                )))
        }
    }

    /// The banner image or its placeholder, clipped to `bannerHeight`, with an
    /// optional spinner overlay while a banner upload is in flight.
    private var bannerImage: some View {
        ZStack {
            BannerImageView(url: bannerUrl)
                .frame(height: bannerHeight)
                .clipped()

            if isUploadingBanner {
                Color.black.opacity(0.35)
                    .frame(height: bannerHeight)
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: bannerHeight)
            }
        }
    }

    // MARK: Avatar subview

    @ViewBuilder
    private var avatarContent: some View {
        if let onPickAvatar {
            // Interactive: wrap in a PhotosPicker with context-menu "Remove"
            PhotosPicker(
                selection: $pickedAvatarItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                avatarImage
                    .overlay(alignment: .bottomTrailing) {
                        editBadge
                            .padding(4)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isUploadingAvatar)
            .accessibilityLabel(Text(NSLocalizedString(
                "Profile photo",
                comment: "Edit Profile: avatar accessibility label"
            )))
            .accessibilityHint(Text(NSLocalizedString(
                "Double-tap to change",
                comment: "Edit Profile: avatar accessibility hint"
            )))
            .contextMenu {
                if avatarUrl != nil, let onRemoveAvatar {
                    Button(role: .destructive) {
                        onRemoveAvatar()
                    } label: {
                        Label(
                            NSLocalizedString("Remove Photo", comment: "Edit Profile: remove avatar context menu item"),
                            systemImage: "trash"
                        )
                    }
                }
            }
        } else {
            // Display-only
            avatarImage
                .accessibilityLabel(Text(NSLocalizedString(
                    "Profile photo",
                    comment: "Profile header: avatar accessibility label"
                )))
        }
    }

    /// The circular avatar with a white border and an optional upload spinner.
    private var avatarImage: some View {
        ZStack {
            ProfileAvatarView(avatarUrl: avatarUrl, name: name, size: avatarSize)
                .overlay(Circle().strokeBorder(.background, lineWidth: 3))

            if isUploadingAvatar {
                Circle()
                    .fill(.black.opacity(0.35))
                    .frame(width: avatarSize, height: avatarSize)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
    }

    /// Small camera badge used in the bottom-trailing corner of both the banner
    /// and the avatar to signal "tappable to edit".
    private var editBadge: some View {
        Image(systemName: "camera.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(.black.opacity(0.55)))
            .accessibilityHidden(true)
    }
}

// MARK: - BannerImageView

/// Loads and displays the banner image from a remote URL, or shows a
/// `secondarySystemBackground` placeholder when the URL is nil or loading fails.
private struct BannerImageView: View {
    let url: URL?

    @Environment(\.imageService) private var imageService
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(UIColor.secondarySystemBackground)
            }
        }
        .task(id: url) {
            await loadBanner()
        }
    }

    private func loadBanner() async {
        image = nil
        guard let url, let imageService else { return }
        // Banner is wide; downsample to 3x the capped width so an iPad does not
        // hold a needlessly large bitmap in memory (cap defined in AdaptiveLayout).
        let screenWidth = UIScreen.main.bounds.width
        let target = CGSize(width: AdaptiveLayout.bannerDownsampleWidth(screenWidth: screenWidth) * 3, height: 300)
        for await state in imageService.fetch(url, downsampleTo: target) {
            if case let .ready(loaded) = state {
                image = loaded
            }
        }
    }
}
