//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI

/// A single tappable Account list row, shared by the signed-in (`AccountView`)
/// and signed-out (`AccountSignedOutView`) screens so the two Account states look
/// identical: a tinted SF Symbol, a title, and a disclosure chevron, in the app's
/// grouped-list style.
///
/// Optional embellishments:
/// - `subtitle` renders a footnote line below the title (e.g. "2 signed in").
/// - `value` renders a secondary trailing label before the chevron (e.g. the
///   current home host on the "Reading from" row).
/// - `isDestructive` tints the row red and drops the chevron (e.g. "Log out").
struct AccountRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    let systemImage: String
    let tint: Color
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.red : tint)
                    .frame(width: 26)
                    // Decorative — the title conveys the row's meaning; skip the
                    // SF Symbol name in the combined VoiceOver announcement.
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(isDestructive ? Color.red : Color(.label))
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                Spacer(minLength: 8)

                if let value, !value.isEmpty {
                    Text(value)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Combine into one VoiceOver element so it reads "<title>, <value>" and is
        // activatable as a button, instead of landing on each label separately.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
