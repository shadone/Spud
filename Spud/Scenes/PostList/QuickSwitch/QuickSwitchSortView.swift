//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SwiftUI

/// The sort picker pushed from the Quick Switch popover. Lists the same sort
/// groups as the toolbar sort menu (actives, Top, comments) via ``PostSortMenu``
/// and applies the selection immediately through the view model, then pops back.
struct QuickSwitchSortView: View {
    let viewModel: QuickSwitchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section { rows(for: PostSortMenu.actives) }
            Section("Top") { rows(for: PostSortMenu.tops) }
            Section { rows(for: PostSortMenu.comments) }
        }
        .navigationTitle("Sort")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rows(for sortTypes: [Components.Schemas.SortType]) -> some View {
        ForEach(sortTypes, id: \.self) { sortType in
            Button {
                viewModel.selectSort(sortType)
                dismiss()
            } label: {
                HStack {
                    let item = sortType.itemForMenu
                    if let symbol = item.imageSystemName {
                        Label(item.title, systemImage: symbol)
                    } else {
                        Text(item.title)
                    }
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
}
