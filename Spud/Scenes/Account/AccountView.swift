//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// The signed-in Account tab content: a tappable profile header over a grouped
/// list of account actions (switch account, saved / activity / your posts / your
/// comments / drafts & outbox, log out). Navigation is owned by the hosting
/// `AccountViewController`, reached through the callbacks wired here, so each row
/// works the same on iPhone and iPad.
struct AccountView: View {
    let viewModel: AccountViewModel
    let accent: Color

    let onEditProfile: () -> Void
    let onSwitchAccount: () -> Void
    let onOpenSaved: () -> Void
    let onOpenActivity: () -> Void
    let onOpenYourPosts: () -> Void
    let onOpenYourComments: () -> Void
    let onOpenDraftsOutbox: () -> Void
    let onLogout: () -> Void

    var body: some View {
        List {
            Section {
                profileHeader
                    // Remove default list-row insets so the banner bleeds
                    // full-width to the section edges, matching the person
                    // profile header appearance.
                    .listRowInsets(EdgeInsets())
            }

            Section {
                AccountRow(
                    title: NSLocalizedString("Switch account", comment: "Account row"),
                    subtitle: switchAccountSubtitle,
                    systemImage: "person.2.crop.square.stack",
                    tint: accent,
                    action: onSwitchAccount
                )
            }

            Section {
                AccountRow(
                    title: NSLocalizedString("Saved", comment: "Account row"),
                    systemImage: "bookmark",
                    tint: accent,
                    action: onOpenSaved
                )
                AccountRow(
                    title: NSLocalizedString("Activity", comment: "Account row"),
                    systemImage: "list.bullet.rectangle.portrait",
                    tint: accent,
                    action: onOpenActivity
                )
                AccountRow(
                    title: NSLocalizedString("Your posts", comment: "Account row"),
                    systemImage: "doc.text",
                    tint: accent,
                    action: onOpenYourPosts
                )
                AccountRow(
                    title: NSLocalizedString("Your comments", comment: "Account row"),
                    systemImage: "text.bubble",
                    tint: accent,
                    action: onOpenYourComments
                )
                AccountRow(
                    title: NSLocalizedString("Drafts & Outbox", comment: "Account row"),
                    systemImage: "tray.2",
                    tint: accent,
                    action: onOpenDraftsOutbox
                )
            }

            Section {
                AccountRow(
                    title: NSLocalizedString("Log out", comment: "Account row"),
                    systemImage: "rectangle.portrait.and.arrow.right",
                    tint: .red,
                    isDestructive: true,
                    action: onLogout
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Profile header

    /// The signed-in profile header: a banner+avatar block (display-only
    /// `ProfileBannerHeaderView`) followed by the display name, handle, and an
    /// "edit" chevron. Tapping anywhere on the header opens the profile editor.
    ///
    /// Layout mirrors the public person profile header (banner behind the avatar)
    /// while keeping the existing edit affordance. The entire block is a single
    /// accessibility element labelled "Edit profile" with a button trait so
    /// VoiceOver users can activate it in one swipe.
    private var profileHeader: some View {
        Button(action: onEditProfile) {
            VStack(alignment: .leading, spacing: 0) {
                // Banner + overlapping avatar (display-only: all callbacks are nil).
                ProfileBannerHeaderView(
                    bannerUrl: viewModel.bannerUrl,
                    avatarUrl: viewModel.avatarUrl,
                    name: headerName,
                    bannerImageOverride: nil,
                    avatarImageOverride: nil,
                    onPickBanner: nil,
                    onPickAvatar: nil,
                    onRemoveBanner: nil,
                    onRemoveAvatar: nil
                )
                // The banner view reserves its own bottom padding for the
                // avatar overlap; add a small gap before the text block.
                .padding(.bottom, 4)

                // Name, handle, and the "edit" disclosure chevron.
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.displayName.isEmpty ? headerName : viewModel.displayName)
                            .font(.headline)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                        if !viewModel.handle.isEmpty {
                            Text(viewModel.handle)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.leading, 16)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.trailing, 16)
                }
                .padding(.bottom, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Collapse the banner + avatar + text into a single VoiceOver element so
        // the user reaches the edit action in a single swipe, matching the
        // previous behaviour (the old HStack also used .combine + isButton).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(NSLocalizedString("Edit profile", comment: "Account header accessibility label")))
        .accessibilityAddTraits(.isButton)
    }

    /// A stable name for the avatar's hue / initial even before the handle text
    /// resolves: prefer the handle, then the display name.
    private var headerName: String {
        if !viewModel.handle.isEmpty {
            return viewModel.handle
        }
        return viewModel.displayName
    }

    private var switchAccountSubtitle: String {
        let count = viewModel.signedInAccountCount
        return String(
            format: NSLocalizedString("%d signed in", comment: "Switch account subtitle: number of signed-in accounts"),
            count
        )
    }
}
