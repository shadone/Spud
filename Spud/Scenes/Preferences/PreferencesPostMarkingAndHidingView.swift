//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SwiftUI

/// The Post Marking & Hiding settings screen. Controls whether posts are
/// marked read on interaction / scroll, and whether read posts are hidden from
/// the feed (live or only at refresh). Every toggle writes through
/// ``PreferencesViewModel`` to ``PreferencesService`` and applies live — the
/// post list observes the same preference streams.
struct PreferencesPostMarkingAndHidingView: View {
    @Bindable var viewModel: PreferencesViewModel

    private var markPostsRead: Binding<Bool> {
        .init { viewModel.markPostsRead } set: { viewModel.updateMarkPostsRead($0) }
    }

    private var markPostsReadOnScroll: Binding<Bool> {
        .init { viewModel.markPostsReadOnScroll } set: { viewModel.updateMarkPostsReadOnScroll($0) }
    }

    private var hideReadPosts: Binding<Bool> {
        .init { viewModel.hideReadPosts } set: { viewModel.updateHideReadPosts($0) }
    }

    private var hideReadPostsMode: Binding<HideReadPostsFilter.Mode> {
        .init { viewModel.hideReadPostsMode } set: { viewModel.updateHideReadPostsMode($0) }
    }

    private var showNsfw: Binding<Bool> {
        .init { viewModel.showNsfw } set: { viewModel.updateShowNsfw($0) }
    }

    private var blurNsfw: Binding<Bool> {
        .init { viewModel.blurNsfw } set: { viewModel.updateBlurNsfw($0) }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Toggle("Mark Posts as Read", isOn: markPostsRead)
                    Text("Posts you interact with are marked as read — for example posts you open or upvote.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                VStack(alignment: .leading) {
                    Toggle("Mark as Read on Scrolling", isOn: markPostsReadOnScroll)
                        .disabled(!viewModel.markPostsRead)
                    Text("Automatically mark posts read as they scroll out of view.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            } header: {
                Text("Posts")
            }

            Section {
                Toggle("Hide Read Posts", isOn: hideReadPosts)

                if viewModel.hideReadPosts {
                    Picker("When", selection: hideReadPostsMode) {
                        Text("On Refresh").tag(HideReadPostsFilter.Mode.onRefresh)
                        Text("Immediately").tag(HideReadPostsFilter.Mode.live)
                    }
                }
            } header: {
                Text("Hide Read")
            } footer: {
                if viewModel.hideReadPosts {
                    switch viewModel.hideReadPostsMode {
                    case .onRefresh:
                        Text("Read posts are removed from the feed when it next refreshes, so nothing disappears while you scroll.")
                    case .live:
                        Text("Read posts are removed from the feed the moment they are marked read.")
                    }
                } else {
                    Text("Read posts stay in the feed.")
                }
            }

            Section {
                Toggle(isOn: showNsfw) {
                    Label(
                        NSLocalizedString("Show NSFW Content", comment: "Settings toggle: show not-safe-for-work content"),
                        systemImage: viewModel.showNsfw ? "eye" : "eye.slash"
                    )
                }
                Toggle(isOn: blurNsfw) {
                    Label(
                        NSLocalizedString("Blur NSFW Content", comment: "Settings toggle: blur not-safe-for-work media"),
                        systemImage: "drop.fill"
                    )
                }
                .disabled(!viewModel.showNsfw)
            } header: {
                Text("NSFW")
            } footer: {
                if viewModel.showNsfw {
                    Text("Blur media in posts and communities marked not-safe-for-work until you tap to reveal.")
                } else {
                    Text("Show posts and communities marked not-safe-for-work. Blur only applies when NSFW content is shown.")
                }
            }
        }
        .navigationTitle("Post Marking & Hiding")
    }
}

#Preview {
    NavigationStack {
        PreferencesPostMarkingAndHidingView(viewModel: PreferencesViewModel())
    }
}
