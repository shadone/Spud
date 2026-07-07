//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SwiftUI

struct PreferencesGeneralView: View {
    let viewModel: PreferencesViewModel

    private var defaultPostSortType: Binding<Lemmy.SortType> {
        .init {
            viewModel.defaultPostSortType
        } set: { newValue in
            viewModel.updateDefaultPostSort(newValue)
        }
    }

    private var defaultCommentSortType: Binding<Lemmy.CommentSortType> {
        .init {
            viewModel.defaultCommentSortType
        } set: { newValue in
            viewModel.updateDefaultCommentSort(newValue)
        }
    }

    private var openExternalLinks: Binding<Preferences.OpenExternalLink> {
        .init {
            viewModel.openExternalLink
        } set: { newValue in
            viewModel.updateOpenExternalLink(newValue)
        }
    }

    private var openInBrowserInstance: Binding<Preferences.LinkInstance> {
        .init {
            viewModel.openInBrowserInstance
        } set: { newValue in
            viewModel.updateOpenInBrowserInstance(newValue)
        }
    }

    private var shareLinkInstance: Binding<Preferences.LinkInstance> {
        .init {
            viewModel.shareLinkInstance
        } set: { newValue in
            viewModel.updateShareLinkInstance(newValue)
        }
    }

    private var openExternalLinkInSafariVCReaderMode: Binding<Bool> {
        .init {
            viewModel.openExternalLinkInSafariVCReaderMode
        } set: { newValue in
            viewModel.updateOpenExternalLinkInSafariVCReaderMode(newValue)
        }
    }

    private var openExternalLinkAsUniversalLinkInApp: Binding<Bool> {
        .init {
            viewModel.openExternalLinkAsUniversalLinkInApp
        } set: { newValue in
            viewModel.updateOpenExternalLinkAsUniversalLinkInApp(newValue)
        }
    }

    private var fetchLinkEmbeds: Binding<Bool> {
        .init { viewModel.fetchLinkEmbeds } set: { viewModel.updateFetchLinkEmbeds($0) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Default Sort", selection: defaultPostSortType) {
                    ForEach(viewModel.allPostSortTypes) { sortType in
                        let item = sortType.itemForMenu
                        if let imageSystemName = item.imageSystemName {
                            Label(item.title, systemImage: imageSystemName)
                                .tag(sortType)
                        } else {
                            Label(item.title, systemImage: "")
                                .tag(sortType)
                        }
                    }
                }
            } header: {
                Text("Posts")
            }

            Section {
                Picker("Default Sort", selection: defaultCommentSortType) {
                    ForEach(viewModel.allCommentSortTypes) { commentSortType in
                        let item = commentSortType.itemForMenu
                        Text(item.title)
                            .tag(commentSortType)
                    }
                }
            } header: {
                Text("Comments")
            }

            Section {
                NavigationLink {
                    PreferencesSwipeActionsView(viewModel: viewModel)
                } label: {
                    Label("Swipe Actions", systemImage: "hand.draw")
                }
            } header: {
                Text("Gestures")
            }

            Section {
                VStack(alignment: .leading) {
                    Picker("Open External Links in", selection: openExternalLinks) {
                        ForEach(Preferences.OpenExternalLink.allCases) { link in
                            let item = link.itemForMenu
                            Label(item.title, systemImage: "")
                                .tag(link)
                        }
                    }

                    switch openExternalLinks.wrappedValue {
                    case .safariViewController:
                        Text("When tapped on an external link it will be opened in an in-app Safari.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    case .browser:
                        Text("When tapped on an external link it will be opened in the default browser.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }

                Toggle("Use Reader Mode", isOn: openExternalLinkInSafariVCReaderMode)

                VStack(alignment: .leading) {
                    Toggle("Open in Apps", isOn: openExternalLinkAsUniversalLinkInApp)
                    Text("If an app is installed that can open handle the link (aka \"universal link\" or \"deep link\"), open in app instead of browser.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                NavigationLink {
                    PreferencesPrivacyView(viewModel: viewModel)
                } label: {
                    Label("Privacy & Link Cleaning", systemImage: "hand.raised")
                }

                Toggle(isOn: fetchLinkEmbeds) {
                    Label(
                        NSLocalizedString("Load Link Previews", comment: "Settings toggle: fetch link preview thumbnails/titles"),
                        systemImage: "rectangle.and.text.magnifyingglass"
                    )
                }
            } header: {
                Text("Links")
            } footer: {
                VStack(alignment: .leading) {
                    Text("Fetch thumbnails and titles for video links in comments and posts. Turn off to keep link previews local and avoid contacting third-party sites.")
                    Spacer(minLength: 8)
                    Text("Testing area:")
                    HStack(spacing: 4) {
                        Text("    - Normal link: [example.com](https://example.com)")
                    }
                    HStack(spacing: 4) {
                        Text("    - Universal link (assuming Youtube app is installed): [youtube.com/foobar](https://youtu.be/dQw4w9WgXcQ)")
                    }
                }
                .environment(\.openURL, OpenURLAction(handler: { url in
                    viewModel.testExternalLink(url)
                    return .handled
                }))
            }

            Section {
                Picker("Open in Browser", selection: openInBrowserInstance) {
                    ForEach(Preferences.LinkInstance.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Share", selection: shareLinkInstance) {
                    ForEach(Preferences.LinkInstance.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
            } header: {
                Text("Post & Comment Links")
            } footer: {
                Text("\"My Instance\" keeps links on your home instance (so you stay signed in). \"Original Instance\" uses the post's source instance.")
            }
        }
        .navigationTitle("General")
    }
}

#Preview {
    NavigationView {
        PreferencesGeneralView(viewModel: PreferencesViewModel())
    }
}
