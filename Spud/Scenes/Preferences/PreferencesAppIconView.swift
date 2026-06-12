//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import SwiftUI
import UIKit

/// The "App Icon" settings screen: the default icon plus each alternate as a
/// selectable swatch. Selecting one calls
/// `UIApplication.setAlternateIconName(_:)` (nil for the default). The flow is
/// entitlement-free — alternate icons declared in `Info.plist` need no special
/// capability. The current selection is read back from
/// `UIApplication.alternateIconName` and reflected with a ring + checkmark.
struct PreferencesAppIconView: View {
    @State private var selected: AppIconVariant = .default
    @State private var failureMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 84), spacing: 20),
    ]

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(AppIconVariant.allCases) { variant in
                        AppIconSwatch(
                            variant: variant,
                            isSelected: variant == selected
                        ) {
                            apply(variant)
                        }
                    }
                }
                .padding(.vertical, 8)
            } footer: {
                Text("Choose how Spud appears on your Home Screen. Icons are placeholder art for now.")
            }
        }
        .navigationTitle("App Icon")
        .onAppear {
            selected = AppIconVariant.current(
                alternateIconName: UIApplication.shared.alternateIconName
            )
        }
        .alert(
            "Couldn't Change Icon",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { failureMessage = nil }
        } message: {
            Text(failureMessage ?? "")
        }
    }

    private func apply(_ variant: AppIconVariant) {
        guard variant != selected else { return }

        // Optimistic-feeling: reflect the choice immediately, then confirm.
        let previous = selected
        selected = variant
        Haptics.tap()

        UIApplication.shared.setAlternateIconName(variant.alternateIconName) { error in
            // setAlternateIconName delivers its completion on the main thread;
            // assumeIsolated lets us touch main-actor state without an async hop.
            MainActor.assumeIsolated {
                if let error {
                    selected = previous
                    Haptics.warning()
                    failureMessage = error.localizedDescription
                } else {
                    Haptics.success()
                }
            }
        }
    }
}

/// A tappable app-icon preview with a rounded-rect mask, selection ring, and
/// checkmark badge.
private struct AppIconSwatch: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let action: () -> Void

    private let side: CGFloat = 72
    private var cornerRadius: CGFloat {
        side * 0.2237
    } // iOS icon squircle ratio

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(variant.previewImageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    Color.accentColor.opacity(isSelected ? 1 : 0),
                                    lineWidth: 3
                                )
                                .padding(-4)
                        }
                        .overlay {
                            // Hairline edge so light icons read against the form
                            // background.
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(.white).padding(3))
                            .offset(x: 6, y: 6)
                    }
                }

                Text(variant.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(variant.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    NavigationStack {
        PreferencesAppIconView()
    }
}
