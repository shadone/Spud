//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SwiftUI

struct PreferencesGeneralView<ViewModel>: View
    where ViewModel: ObservableObject & PreferencesViewModelType
{
    @StateObject var viewModel: ViewModel

    var defaultPostSortType: Binding<SortType> {
        .init {
            viewModel.outputs.defaultPostSortType.value
        } set: { newValue in
            viewModel.inputs.updateDefaultPostSort(newValue)
        }
    }

    var defaultCommentSortType: Binding<CommentSortType> {
        .init {
            viewModel.outputs.defaultCommentSortType.value
        } set: { newValue in
            viewModel.inputs.updateDefaultCommentSort(newValue)
        }
    }

    var openExternalLinks: Binding<Preferences.OpenExternalLink> {
        .init {
            viewModel.outputs.openExternalLink.value
        } set: { newValue in
            viewModel.inputs.updateOpenExternalLink(newValue)
        }
    }

    var openExternalLinkInSafariVCReaderMode: Binding<Bool> {
        .init {
            viewModel.outputs.openExternalLinkInSafariVCReaderMode.value
        } set: { newValue in
            viewModel.inputs.updateOpenExternalLinkInSafariVCReaderMode(newValue)
        }
    }

    var openExternalLinkAsUniversalLinkInApp: Binding<Bool> {
        .init {
            viewModel.outputs.openExternalLinkAsUniversalLinkInApp.value
        } set: { newValue in
            viewModel.inputs.updateOpenExternalLinkAsUniversalLinkInApp(newValue)
        }
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PreferencesPostMarkingAndHidingView()
                } label: {
                    Text("Mark Read / Hiding Posts")
                }

                Picker("Default Sort", selection: defaultPostSortType) {
                    ForEach(viewModel.outputs.allPostSortTypes) { sortType in
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
                    ForEach(viewModel.outputs.allCommentSortTypes) { commentSortType in
                        let item = commentSortType.itemForMenu
                            Text(item.title)
                                .tag(commentSortType)
                    }
                }
            } header: {
                Text("Comments")
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
            } header: {
                Text("Links")
            } footer: {
                VStack(alignment: .leading) {
                    Text("Testing area:")
                    HStack(spacing: 4) {
                        Text("    - Normal link: [example.com](https://example.com)")
                    }
                    HStack(spacing: 4) {
                        Text("    - Universal link (assuming Youtube app is installed): [youtube.com/foobar](https://youtu.be/dQw4w9WgXcQ)")
                    }
                }
                .environment(\.openURL, OpenURLAction(handler: { url in
                    viewModel.inputs.testExternalLink(url)
                    return .handled
                }))
            }
        }
        .navigationTitle("General")
    }
}

struct PreferencesGeneralView_Preview: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PreferencesGeneralView(
                viewModel: PreferencesViewModelForPreview()
            )
        }
    }
}
