//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import PhotosUI
import SpudDataKit
import SwiftUI

/// The Edit Profile editor: a grouped Form that edits the signed-in account's
/// display name, bio, and avatar, plus the server-synced preference flags and
/// default feed. Save / Cancel live in the nav bar; on save success the view
/// model signals the host to dismiss.
struct EditProfileView: View {
    @Bindable var viewModel: EditProfileViewModel
    let accent: Color
    /// Invoked when the user taps Cancel. Dismissal is owned by the host so the
    /// same path works whether the editor is pushed or presented modally.
    let onCancel: () -> Void

    /// The Photos pick, loaded as `Data` and handed to the view model to JPEG +
    /// upload. Cleared after each pick so the same photo can be re-picked.
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        Form {
            avatarSection
            profileSection
            preferencesSection
        }
        .navigationTitle(Text(verbatim: NSLocalizedString("Edit Profile", comment: "Edit Profile screen title")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .tint(accent)
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.isUploadingAvatar)
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.uploadAvatar(imageData: data)
                }
                pickedItem = nil
            }
        }
        .alert(
            Text(verbatim: NSLocalizedString("Something went wrong", comment: "Edit Profile error alert title")),
            isPresented: errorBinding,
            presenting: errorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "Error alert dismiss")) {
                viewModel.clearError()
            }
        } message: { message in
            Text(message)
        }
    }

    // MARK: Sections

    private var avatarSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    ProfileAvatarView(avatarUrl: viewModel.avatarUrl, name: viewModel.name, size: 60)
                    if viewModel.isUploadingAvatar {
                        Circle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 60, height: 60)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(
                        selection: $pickedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Text(NSLocalizedString("Change Photo", comment: "Edit Profile: pick a new avatar"))
                    }
                    .disabled(viewModel.isUploadingAvatar)

                    if viewModel.avatarUrl != nil {
                        Button(role: .destructive) {
                            viewModel.removeAvatar()
                        } label: {
                            Text(NSLocalizedString("Remove Photo", comment: "Edit Profile: clear the avatar"))
                        }
                        .disabled(viewModel.isUploadingAvatar)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var profileSection: some View {
        Section {
            TextField(
                NSLocalizedString("Display name", comment: "Edit Profile field label"),
                text: $viewModel.displayName
            )
            .textInputAutocapitalization(.words)

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Bio", comment: "Edit Profile field label"))
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                TextEditor(text: $viewModel.bio)
                    .frame(minHeight: 120)
                    .font(.body)
                    .accessibilityLabel(Text(NSLocalizedString("Bio", comment: "Edit Profile bio accessibility label")))
            }
            .padding(.vertical, 4)
        } header: {
            Text(NSLocalizedString("Profile", comment: "Edit Profile section header"))
        } footer: {
            Text(NSLocalizedString(
                "Your bio supports Markdown.",
                comment: "Edit Profile bio footer"
            ))
        }
    }

    private var preferencesSection: some View {
        Section {
            Toggle(
                NSLocalizedString("Show scores", comment: "Edit Profile preference toggle"),
                isOn: $viewModel.showScores
            )
            Toggle(
                NSLocalizedString("Show bot accounts", comment: "Edit Profile preference toggle"),
                isOn: $viewModel.showBotAccounts
            )
            Toggle(
                NSLocalizedString("Show read posts", comment: "Edit Profile preference toggle"),
                isOn: $viewModel.showReadPosts
            )
            Toggle(
                NSLocalizedString("Show others' avatars", comment: "Edit Profile preference toggle"),
                isOn: $viewModel.showAvatars
            )

            Picker(
                NSLocalizedString("Default feed", comment: "Edit Profile default feed picker"),
                selection: $viewModel.defaultListingType
            ) {
                Text(NSLocalizedString("All", comment: "Default feed option")).tag(Components.Schemas.ListingType.All)
                Text(NSLocalizedString("Local", comment: "Default feed option")).tag(Components.Schemas.ListingType.Local)
                Text(NSLocalizedString("Subscribed", comment: "Default feed option")).tag(Components.Schemas.ListingType.Subscribed)
            }
        } header: {
            Text(NSLocalizedString("Preferences", comment: "Edit Profile section header"))
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("Cancel", comment: "Edit Profile cancel button")) {
                onCancel()
            }
            .disabled(viewModel.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.isSaving {
                ProgressView()
            } else {
                Button(NSLocalizedString("Save", comment: "Edit Profile save button")) {
                    Task { await viewModel.save() }
                }
                .disabled(!viewModel.canSave)
            }
        }
    }

    // MARK: Error alert plumbing

    private var errorMessage: String? {
        if case let .failed(message) = viewModel.saveState {
            return message
        }
        return nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { presented in
                if !presented { viewModel.clearError() }
            }
        )
    }
}
