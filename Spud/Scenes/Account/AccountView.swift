//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// The signed-in Account tab content: a tappable profile header over a grouped
/// list of account actions (switch account, saved / your posts / your comments,
/// log out). Navigation is owned by the hosting `AccountViewController`, reached
/// through the callbacks wired here, so each row works the same on iPhone and
/// iPad.
struct AccountView: View {
    let viewModel: AccountViewModel
    let accent: Color

    let onEditProfile: () -> Void
    let onSwitchAccount: () -> Void
    let onOpenSaved: () -> Void
    let onOpenHistory: () -> Void
    let onOpenYourPosts: () -> Void
    let onOpenYourComments: () -> Void
    let onLogout: () -> Void

    var body: some View {
        List {
            Section {
                profileHeader
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
                    title: NSLocalizedString("History", comment: "Account row"),
                    systemImage: "clock.arrow.circlepath",
                    tint: accent,
                    action: onOpenHistory
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

    private var profileHeader: some View {
        Button(action: onEditProfile) {
            HStack(spacing: 14) {
                ProfileAvatarView(
                    avatarUrl: viewModel.avatarUrl,
                    name: headerName,
                    size: 60
                )

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

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
