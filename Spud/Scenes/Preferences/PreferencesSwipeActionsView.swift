//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import SwiftUI

/// Apollo-style swipe-action configuration: assign each of the four gesture
/// slots (short/long, leading/trailing) for posts and for comments, with a
/// reset-to-defaults per kind. Writes flow straight through the view model to
/// `PreferencesService`, so visible cells update live.
struct PreferencesSwipeActionsView: View {
    let viewModel: PreferencesViewModel

    var body: some View {
        Form {
            slotSection(
                kind: .post,
                header: NSLocalizedString("Posts", comment: "Swipe-actions settings section: posts"),
                config: viewModel.postSwipeActions,
                set: { viewModel.updatePostSwipeAction($0, for: $1) }
            )

            Section {
                Button(role: .destructive) {
                    viewModel.resetPostSwipeActions()
                } label: {
                    Text("Reset Post Swipe Actions")
                }
            }

            slotSection(
                kind: .comment,
                header: NSLocalizedString("Comments", comment: "Swipe-actions settings section: comments"),
                config: viewModel.commentSwipeActions,
                set: { viewModel.updateCommentSwipeAction($0, for: $1) }
            )

            Section {
                Button(role: .destructive) {
                    viewModel.resetCommentSwipeActions()
                } label: {
                    Text("Reset Comment Swipe Actions")
                }
            } footer: {
                Text("A short swipe triggers the first action in each direction; a long swipe triggers the second.")
            }
        }
        .navigationTitle("Swipe Actions")
    }

    /// A section of four slot pickers for one content kind.
    private func slotSection(
        kind: SwipeActionContentKind,
        header: String,
        config: SwipeActionConfig,
        set: @escaping (SwipeAction, SwipeActionSlot) -> Void
    ) -> some View {
        Section {
            ForEach(SwipeActionSlot.allCases) { slot in
                slotPicker(slot: slot, kind: kind, current: config.action(for: slot), set: set)
            }
        } header: {
            Text(header)
        }
    }

    private func slotPicker(
        slot: SwipeActionSlot,
        kind: SwipeActionContentKind,
        current: SwipeAction,
        set: @escaping (SwipeAction, SwipeActionSlot) -> Void
    ) -> some View {
        let binding = Binding<SwipeAction> {
            current
        } set: { newValue in
            set(newValue, slot)
        }
        return Picker(slot.settingsTitle, selection: binding) {
            ForEach(kind.assignableActions) { action in
                Label(action.pickerTitle, systemImage: action.pickerSystemImageName)
                    .tag(action)
            }
        }
    }
}

private extension SwipeActionSlot {
    /// User-facing label for the slot in settings.
    var settingsTitle: String {
        switch self {
        case .leadingPrimary:
            return NSLocalizedString("Right Swipe (Short)", comment: "Swipe slot: leading short")
        case .leadingSecondary:
            return NSLocalizedString("Right Swipe (Long)", comment: "Swipe slot: leading long")
        case .trailingPrimary:
            return NSLocalizedString("Left Swipe (Short)", comment: "Swipe slot: trailing short")
        case .trailingSecondary:
            return NSLocalizedString("Left Swipe (Long)", comment: "Swipe slot: trailing long")
        }
    }
}

#Preview {
    NavigationView {
        PreferencesSwipeActionsView(viewModel: PreferencesViewModel())
    }
}
