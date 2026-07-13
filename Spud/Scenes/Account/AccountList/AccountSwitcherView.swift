//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// The account-switcher bottom sheet content: a centered "Accounts" title over
/// an inset-grouped list with a "Signed in" section, an "Anonymous" section, and
/// a pair of accent action rows ("Log into another account", "Browse an instance
/// anonymously").
///
/// Each account row carries a trailing radio check — a filled-accent circle with
/// a white checkmark for the active/default account, an empty ring otherwise.
/// The selection is conveyed non-visually too: the active row is published as a
/// `.isSelected` accessibility trait, so VoiceOver reads it without relying on
/// color.
///
/// Navigation and persistence are owned by the hosting controller, reached via
/// the callbacks wired here. Hosted in a `UIHostingController` presented as a
/// medium/large detent sheet (see `AccountListViewController`).
///
/// The view reads its account rows straight from the `@Observable`
/// ``AccountSwitcherViewModel``, so SwiftUI re-renders itself whenever the DB
/// observation emits (an account added/removed, or the default switched) — no
/// hand-rolled relay in the hosting controller.
struct AccountSwitcherView: View {
    /// The live view model. Its `rows` (all non-service accounts from
    /// `observeAccountListRows()`, in observation order) drive the list; reading
    /// `viewModel.rows` here registers the SwiftUI dependency, so the open sheet
    /// stays in sync without the controller re-pushing a new view tree.
    let viewModel: AccountSwitcherViewModel
    let accent: Color

    /// Selects an account as the default and dismisses.
    let onSelect: (_ accountKeychainId: String) -> Void
    /// Removes an account (swipe-to-delete). Offered only for a NON-active
    /// account — you switch away from the active one rather than delete it,
    /// which keeps the app from ever being left without a default.
    let onRemove: (_ accountKeychainId: String) -> Void
    /// Launches the in-place re-auth flow for a row whose `sessionNeedsReauth`
    /// is set. Present alongside `onSelect` (rather than folded into it) since a
    /// flagged row's "Re-login" affordance is a separate tap target from the row
    /// itself, which still just switches to it.
    let onReauth: (_ accountKeychainId: String) -> Void
    /// Opens the add-account flow (server picker -> log in / sign up).
    let onAddAccount: () -> Void
    /// Opens the anonymous-browse flow (server picker -> "Browse anonymously").
    let onBrowseAnonymously: () -> Void

    private var signedInRows: [AccountListRow] {
        viewModel.rows.filter { !$0.isSignedOutAccountType }
    }

    private var anonymousRows: [AccountListRow] {
        viewModel.rows.filter(\.isSignedOutAccountType)
    }

    var body: some View {
        VStack(spacing: 0) {
            title

            List {
                if !signedInRows.isEmpty {
                    signedInSection
                }

                if !anonymousRows.isEmpty {
                    anonymousSection
                }

                actionsSection
            }
            .listStyle(.insetGrouped)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Title

    /// The sheet's own centered, bold "Accounts" title. The sheet supplies its
    /// own grabber; there is no nav bar.
    private var title: some View {
        Text(NSLocalizedString("Accounts", comment: "Account switcher sheet title"))
            .font(.headline)
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Sections

    private var signedInSection: some View {
        Section {
            ForEach(signedInRows) { row in
                accountRow(row)
            }
        } header: {
            Text(NSLocalizedString("Signed in", comment: "Account switcher section header"))
        }
    }

    private var anonymousSection: some View {
        Section {
            ForEach(anonymousRows) { row in
                accountRow(row)
            }
        } header: {
            Text(NSLocalizedString("Anonymous", comment: "Account switcher section header"))
        } footer: {
            Text(NSLocalizedString(
                "Anonymous on an instance shows exactly what that server federates — which can differ from your logged-in view.",
                comment: "Account switcher anonymous-section footnote"
            ))
        }
    }

    private var actionsSection: some View {
        Section {
            AccountSwitcherActionRow(
                systemImage: "plus",
                title: NSLocalizedString("Log into another account", comment: "Account switcher action"),
                accent: accent,
                action: onAddAccount
            )
            AccountSwitcherActionRow(
                systemImage: "eye",
                title: NSLocalizedString("Browse an instance anonymously", comment: "Account switcher action"),
                accent: accent,
                action: onBrowseAnonymously
            )
        }
    }

    // MARK: Account row

    /// One account row. Signed-in rows show the person avatar + display name +
    /// `@name@instance`; anonymous rows show an eye tile + "Browsing
    /// anonymously" + "on <instance>". A non-active account is swipe-deletable;
    /// the active account is not (you switch away from it instead).
    private func accountRow(_ row: AccountListRow) -> some View {
        AccountSwitcherAccountRow(row: row, accent: accent) {
            onSelect(row.accountKeychainId)
        } onReauth: {
            onReauth(row.accountKeychainId)
        }
        // The active account is the one you'd switch *to* — deleting it would
        // leave the app without a default, so only non-active rows are
        // swipe-deletable.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !row.isDefault {
                Button(role: .destructive) {
                    onRemove(row.accountKeychainId)
                } label: {
                    Label(
                        NSLocalizedString("Remove", comment: "Account switcher remove account swipe action"),
                        systemImage: "trash"
                    )
                }
            }
        }
    }
}

/// A single account row in the switcher: a leading avatar (or eye tile for
/// anonymous accounts), the name + monospaced handle, and a trailing radio
/// check. Tapping the row selects the account.
private struct AccountSwitcherAccountRow: View {
    let row: AccountListRow
    let accent: Color
    let action: () -> Void
    let onReauth: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText)
                        .font(.body)
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                    Text(secondaryText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if row.sessionNeedsReauth {
                    Button {
                        onReauth()
                    } label: {
                        Text(NSLocalizedString("Re-login", comment: "Account switcher per-account re-login affordance"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    // The row collapses into a single VoiceOver element
                    // (`.accessibilityElement(children: .ignore)` below), which
                    // discards this inner button. Hide it explicitly and expose
                    // re-login as a custom action on the combined element instead,
                    // so VoiceOver can still reach it.
                    .accessibilityHidden(true)
                }

                RadioCheck(isSelected: row.isDefault, accent: accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Combine the row into one VoiceOver element, label it with the human
        // text (with a "needs re-login" clause when flagged), and surface
        // selection as a trait (not by color alone) so the active account is
        // announced as "selected".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(row.isDefault ? [.isButton, .isSelected] : .isButton)
        // The visible "Re-login" button is hidden from VoiceOver (see above);
        // surface it here as a custom action on the row's single element so a
        // VoiceOver user on a flagged row can trigger re-login directly.
        .accessibilityActions {
            if row.sessionNeedsReauth {
                Button(NSLocalizedString("Re-login", comment: "Account switcher re-login accessibility action")) {
                    onReauth()
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if row.isSignedOutAccountType {
            AnonymousAccountTile(size: 40)
        } else {
            ProfileAvatarView(
                avatarUrl: row.avatarUrl,
                name: row.nickname ?? row.instanceHostname,
                size: 40
            )
        }
    }

    /// The bold first line: the display name when signed in, a fixed
    /// "Browsing anonymously" when anonymous.
    private var primaryText: String {
        if row.isSignedOutAccountType {
            return NSLocalizedString("Browsing anonymously", comment: "Account switcher anonymous row title")
        }
        return row.nickname ?? row.instanceHostname
    }

    /// The monospaced secondary line: the true `@username@instance` handle when
    /// signed in, "on <instance>" when anonymous. Uses the raw `person.name`
    /// username (never the display-name-first `nickname`) so a user whose display
    /// name is e.g. "Ada Lovelace" still shows `@ada@instance`, mirroring how
    /// `AccountViewModel` builds the header handle.
    private var secondaryText: String {
        if row.isSignedOutAccountType {
            return String(
                format: NSLocalizedString("on %@", comment: "Account switcher anonymous row subtitle, %@ is the instance host"),
                row.instanceHostname
            )
        }
        return "@\(row.name ?? row.instanceHostname)@\(row.instanceHostname)"
    }

    private var accessibilityLabel: String {
        let base = "\(primaryText), \(secondaryText)"
        guard row.sessionNeedsReauth else { return base }
        // Announce the expired-session state on the combined element so a
        // VoiceOver user hears WHY re-login is offered, not just the handle.
        let needsReauth = NSLocalizedString(
            "session expired, needs re-login",
            comment: "Account switcher row accessibility clause when the account's session expired"
        )
        return "\(base), \(needsReauth)"
    }
}

/// The "eye" tile shown in place of an avatar for an anonymous account: a filled
/// rounded square with a centered eye glyph, matching the design.
private struct AnonymousAccountTile: View {
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "eye")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Color(.secondaryLabel))
            )
    }
}

/// The trailing radio check accessory: a filled-accent circle with a white
/// checkmark when the account is the active/default one, an empty ring
/// otherwise. Purely decorative — the selection is announced via the row's
/// `.isSelected` accessibility trait, so this is hidden from VoiceOver.
private struct RadioCheck: View {
    let isSelected: Bool
    let accent: Color

    var body: some View {
        Group {
            if isSelected {
                Circle()
                    .fill(accent)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )
            } else {
                Circle()
                    .strokeBorder(Color(.tertiaryLabel), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An accent action row in the switcher's final card: a dashed-circle SF Symbol
/// glyph and an accent-tinted title. Used for "Log into another account" and
/// "Browse an instance anonymously".
private struct AccountSwitcherActionRow: View {
    let systemImage: String
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            accent,
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.body)
                    .foregroundStyle(accent)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}
