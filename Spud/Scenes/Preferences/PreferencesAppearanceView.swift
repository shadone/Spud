//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import SwiftUI

/// The Appearance settings screen: a theme picker (System / Light / Dark /
/// True Black) and an accent-color swatch grid. Both apply live, app-wide,
/// the moment they're tapped — the window observes the preference streams.
struct PreferencesAppearanceView: View {
    let viewModel: PreferencesViewModel

    private var appTheme: Binding<AppTheme> {
        .init {
            viewModel.appTheme
        } set: { newValue in
            viewModel.updateAppTheme(newValue)
        }
    }

    private let swatchColumns = [
        GridItem(.adaptive(minimum: 56), spacing: 16),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: appTheme) {
                    ForEach(viewModel.allAppThemes) { theme in
                        Label(theme.title, systemImage: theme.symbolName)
                            .tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Theme")
            } footer: {
                Text("True Black uses pure-black backgrounds to save power on OLED displays.")
            }

            Section {
                LazyVGrid(columns: swatchColumns, spacing: 16) {
                    ForEach(viewModel.allAccentColors) { accent in
                        AccentSwatch(
                            accent: accent,
                            isSelected: accent == viewModel.accentColor
                        ) {
                            viewModel.updateAccentColor(accent)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent Color")
            }

            Section {
                NavigationLink {
                    PreferencesAppIconView()
                } label: {
                    Label("App Icon", systemImage: "app.badge")
                }
            }
        }
        .navigationTitle("Appearance")
    }
}

/// A tappable accent-color swatch with a selection ring and checkmark.
private struct AccentSwatch: View {
    let accent: AccentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.swiftUIColor)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.primary.opacity(isSelected ? 0.9 : 0),
                                    lineWidth: 3
                                )
                                .padding(-3)
                        }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(accent.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    NavigationStack {
        PreferencesAppearanceView(viewModel: PreferencesViewModel())
    }
}
