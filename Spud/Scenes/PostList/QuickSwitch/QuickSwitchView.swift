//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import SwiftUI

/// The Quick Switch popover: in-feed controls for how the post list renders —
/// density, thumbnail position, and vote-button visibility — plus a Sort row
/// that pushes the full sort picker. Hosted from the post-list toolbar; writes
/// go straight through ``PreferencesService`` via the view model, so the feed
/// re-flows live.
struct QuickSwitchView: View {
    let viewModel: QuickSwitchViewModel

    private var postDensity: Binding<PostDensity> {
        .init { viewModel.postDensity } set: { viewModel.updatePostDensity($0) }
    }

    private var thumbnailPosition: Binding<ThumbnailPosition> {
        .init { viewModel.thumbnailPosition } set: { viewModel.updateThumbnailPosition($0) }
    }

    private var showVoteButtons: Binding<Bool> {
        .init { viewModel.showVoteButtons } set: { viewModel.updateShowVoteButtons($0) }
    }

    private var showNsfw: Binding<Bool> {
        .init { viewModel.showNsfw } set: { viewModel.updateShowNsfw($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Density") {
                    Picker("Density", selection: postDensity) {
                        ForEach(viewModel.allPostDensities) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Thumbnail") {
                    Picker("Thumbnail", selection: thumbnailPosition) {
                        ForEach(viewModel.allThumbnailPositions) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle(isOn: showVoteButtons) {
                        Label("Vote Buttons", systemImage: "arrow.up.arrow.down")
                    }
                }

                Section {
                    Toggle(isOn: showNsfw) {
                        Label("Show NSFW", systemImage: viewModel.showNsfw ? "eye" : "eye.slash")
                    }
                } footer: {
                    Text("Show posts marked not-safe-for-work.")
                }

                Section {
                    NavigationLink {
                        QuickSwitchSortView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Label("Sort", systemImage: "line.horizontal.3.decrease.circle")
                            Spacer()
                            Text(viewModel.currentSort.itemForMenu.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    QuickSwitchView(
        viewModel: QuickSwitchViewModel(
            preferencesService: PreferencesService(),
            currentSort: .Hot,
            onSelectSort: { _ in }
        )
    )
}
