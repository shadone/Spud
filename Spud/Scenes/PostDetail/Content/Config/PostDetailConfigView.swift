//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import SwiftUI

/// The post-detail config popover: comment density plus a Sort row that pushes
/// the comment-sort picker. Hosted from the post-detail toolbar; density writes
/// through ``PreferencesService`` (live re-flow), sort routes per-post.
struct PostDetailConfigView: View {
    let viewModel: PostDetailConfigViewModel

    private var commentDensity: Binding<PostDensity> {
        .init { viewModel.commentDensity } set: { viewModel.updateCommentDensity($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Density") {
                    Picker("Density", selection: commentDensity) {
                        ForEach(viewModel.allCommentDensities) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    NavigationLink {
                        PostDetailConfigSortView(viewModel: viewModel)
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
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    PostDetailConfigView(
        viewModel: PostDetailConfigViewModel(
            preferencesService: PreferencesService(),
            currentSort: .Hot,
            onSelectSort: { _ in }
        )
    )
}
