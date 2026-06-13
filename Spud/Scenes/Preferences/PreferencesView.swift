//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI

struct PreferencesView: View {
    let viewModel: PreferencesViewModel

    /// One blocked-list view model shared by both sub-screens, so they fetch
    /// once and stay in sync. nil for signed-out accounts (which can't block)
    /// and the preview init.
    private let blockedListViewModel: BlockedListViewModel?

    /// Backs the "Hidden & Muted" management screen. Available signed-out too
    /// (muting is local); nil only in the preview init.
    private let hiddenAndMutedViewModel: HiddenAndMutedViewModel?

    init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
        blockedListViewModel = viewModel.makeBlockedListViewModel()
        hiddenAndMutedViewModel = viewModel.makeHiddenAndMutedViewModel()
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink {
                        PreferencesGeneralView(viewModel: viewModel)
                    } label: {
                        Label("General", systemImage: "gear")
                    }

                    NavigationLink {
                        PreferencesAppearanceView(viewModel: viewModel)
                    } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }

                    NavigationLink {
                        PreferencesDisplayView(viewModel: viewModel)
                    } label: {
                        Label("Display", systemImage: "rectangle.grid.1x2")
                    }

                    NavigationLink {
                        PreferencesPostMarkingAndHidingView(viewModel: viewModel)
                    } label: {
                        Label("Post Marking & Hiding", systemImage: "eye.slash")
                    }

                    if let hiddenAndMutedViewModel {
                        NavigationLink {
                            PreferencesHiddenAndMutedView(viewModel: hiddenAndMutedViewModel)
                        } label: {
                            Label("Hidden & Muted", systemImage: "eye.slash.circle")
                        }
                    }

                    NavigationLink { } label: {
                        Label("Accounts", systemImage: "person")
                    }
                }

                // Safety / moderation: blocked-list management. Hidden for
                // signed-out accounts, which can't block.
                if !viewModel.isSignedOut, let blockedListViewModel {
                    Section {
                        NavigationLink {
                            PreferencesBlockedUsersView(viewModel: blockedListViewModel)
                        } label: {
                            Label("Blocked Users", systemImage: "hand.raised")
                        }

                        NavigationLink {
                            PreferencesBlockedCommunitiesView(viewModel: blockedListViewModel)
                        } label: {
                            Label("Blocked Communities", systemImage: "hand.raised.square")
                        }
                    } header: {
                        Text("Safety")
                    }
                }

                Section {
                    NavigationLink {
                        PreferencesAboutView(viewModel: viewModel)
                    } label: {
                        Label("About", systemImage: "a")
                    }
                }
            }
        }
    }
}

#Preview {
    PreferencesView(viewModel: PreferencesViewModel())
}
