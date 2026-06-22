//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SwiftUI

/// The comment-sort picker pushed from the post-detail config popover. Lists the
/// `CommentSortType` cases, applies the selection immediately through the view
/// model, then pops back.
struct PostDetailConfigSortView: View {
    let viewModel: PostDetailConfigViewModel
    @Environment(\.dismiss) private var dismiss

    private let sortTypes: [Components.Schemas.CommentSortType] = [.Hot, .Top, .New, .Old, .Controversial]

    var body: some View {
        List {
            ForEach(sortTypes, id: \.self) { sortType in
                Button {
                    viewModel.selectSort(sortType)
                    dismiss()
                } label: {
                    HStack {
                        Text(sortType.itemForMenu.title)
                        Spacer()
                        if sortType == viewModel.currentSort {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .tint(.primary)
            }
        }
        .navigationTitle("Sort")
        .navigationBarTitleDisplayMode(.inline)
    }
}
