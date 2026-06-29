//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI

/// The signed-out (anonymous) Account tab content: a grouped screen that explains
/// anonymous browsing and offers the ways in. Mirrors the signed-in `AccountView`'s
/// `.insetGrouped` style for consistency: a centered header (avatar placeholder +
/// title + subtitle), a "Reading from <host>" row to change the home server, the
/// prominent Create account / Log in buttons, and a Settings row.
///
/// Navigation is owned by the hosting `AccountViewController`, reached through the
/// callbacks wired here, so each control works the same on iPhone and iPad.
struct AccountSignedOutView: View {
    /// The current anonymous account's home instance host, e.g. "lemmy.world",
    /// shown in the "Reading from" row. May be empty before the account resolves.
    let instanceHostname: String
    let accent: Color

    /// Opens the account switcher (its "Browse an instance anonymously" path lets
    /// you change the home server, alongside the list of accounts).
    let onChangeInstance: () -> Void
    /// Opens the add-account flow (instance picker -> sign up).
    let onCreateAccount: () -> Void
    /// Opens the add-account flow (instance picker -> log in).
    let onLogIn: () -> Void
    /// Pushes Preferences.
    let onSettings: () -> Void

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                AccountRow(
                    title: NSLocalizedString("Reading from", comment: "Signed-out account: home server row title"),
                    value: instanceHostname,
                    systemImage: "globe",
                    tint: accent,
                    action: onChangeInstance
                )
            } footer: {
                Text(NSLocalizedString(
                    "You can change your home server any time — it doesn't limit what you can read.",
                    comment: "Signed-out account: home-server section footer"
                ))
            }

            Section {
                Button(action: onCreateAccount) {
                    Text(NSLocalizedString("Create account", comment: "Signed-out account: create-account button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button(action: onLogIn) {
                    Text(NSLocalizedString("Log in", comment: "Signed-out account: log-in button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color(.label))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                AccountRow(
                    title: NSLocalizedString("Settings", comment: "Account row"),
                    systemImage: "gearshape",
                    tint: accent,
                    action: onSettings
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Header

    /// The centered guest header: a neutral circular avatar placeholder over a
    /// bold title and an explanatory subtitle. Combined into a single VoiceOver
    /// element so it reads as one descriptive statement, not three fragments.
    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 76, height: 76)
                Image(systemName: "person.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(.secondaryLabel))
            }

            VStack(spacing: 6) {
                Text(NSLocalizedString("Browsing anonymously", comment: "Signed-out account header title"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(.label))

                Text(NSLocalizedString(
                    "You can read anything on Spud without an account. Sign in to vote, comment and subscribe.",
                    comment: "Signed-out account header subtitle"
                ))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
