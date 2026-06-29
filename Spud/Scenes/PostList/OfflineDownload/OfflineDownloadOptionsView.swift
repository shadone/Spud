//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import SwiftUI

/// The chooser shown before an offline download starts: a short explanation, a
/// post-count picker, and Cancel / Download actions. On Download it hands the
/// chosen count back to the hosting controller (which dismisses the chooser and
/// presents the progress sheet).
///
/// Driven by ``OfflineDownloadOptionsViewModel`` (`@Observable`), whose
/// selection is seeded from and persisted back to ``PreferencesService`` so the
/// chooser remembers the last choice. A `Form` so it reads as a native settings
/// chooser, consistent with the Quick Switch popover and other SwiftUI sheets.
struct OfflineDownloadOptionsView: View {
    let viewModel: OfflineDownloadOptionsViewModel

    @Environment(\.dismiss) private var dismiss

    private var postCount: Binding<Preferences.OfflineDownloadPostCount> {
        .init { viewModel.postCount } set: { viewModel.updatePostCount($0) }
    }

    private var archiveLinks: Binding<Bool> {
        .init { viewModel.archiveLinks } set: { viewModel.updateArchiveLinks($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        selection: postCount
                    ) {
                        ForEach(viewModel.allPostCounts) { count in
                            Text(count.title).tag(count)
                        }
                    } label: {
                        Label(
                            NSLocalizedString(
                                "Posts to save",
                                comment: "Offline download chooser: post-count picker label"
                            ),
                            systemImage: "square.stack.3d.up"
                        )
                    }
                } footer: {
                    Text(NSLocalizedString(
                        "Saves the top posts of this feed — with their comments and images — for offline reading.",
                        comment: "Offline download chooser footer explaining what's saved"
                    ))
                }

                Section {
                    Toggle(isOn: archiveLinks) {
                        Label(
                            NSLocalizedString(
                                "Also save linked web pages",
                                comment: "Offline download chooser: toggle to also web-archive external-link posts"
                            ),
                            systemImage: "safari"
                        )
                    }
                } footer: {
                    Text(NSLocalizedString(
                        "Saves a copy of each linked web page so it can be read offline. This is slower and uses more space.",
                        comment: "Offline download chooser footer explaining the save-linked-pages toggle"
                    ))
                }

                Section {
                    Button {
                        // Hand the choice back first; the controller dismisses
                        // this chooser and presents the progress sheet.
                        viewModel.start()
                    } label: {
                        Label(
                            NSLocalizedString(
                                "Download",
                                comment: "Offline download chooser: start button"
                            ),
                            systemImage: "arrow.down.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(Text(NSLocalizedString(
                "Download for offline",
                comment: "Title of the offline-download options chooser sheet"
            )))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString(
                        "Cancel",
                        comment: "Cancel button on the offline-download options chooser"
                    )) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    OfflineDownloadOptionsView(
        viewModel: OfflineDownloadOptionsViewModel(
            preferencesService: PreferencesService(),
            onStart: { _, _ in }
        )
    )
}
