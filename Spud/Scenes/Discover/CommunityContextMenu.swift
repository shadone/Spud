//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI
import UIKit

/// Long-press context menu for a community row across the Discover surfaces
/// (directory, rails, packs, instance lens), recreated from the Discover design.
/// Covers the actions the app can drive for an Explorer community: Open, Subscribe,
/// Mute, Share, Copy Link, Block. The design's Favourite and Add-to-group items
/// are intentionally omitted — neither feature exists in the app yet.
struct CommunityContextMenu: View {
    let row: CommunityListRow
    let viewModel: DiscoverViewModel

    var body: some View {
        Button {
            viewModel.open(row)
        } label: {
            Label("Open Community", systemImage: "arrow.up.forward.app")
        }

        let subscribed = viewModel.subscriptionState(for: row) == .subscribed
        Button {
            viewModel.toggleSubscription(row)
        } label: {
            Label(subscribed ? "Unsubscribe" : "Subscribe", systemImage: subscribed ? "checkmark" : "plus")
        }

        Divider()

        if viewModel.isMuted(row) {
            Button {
                viewModel.unmute(row)
            } label: {
                Label("Unmute", systemImage: "bell")
            }
        } else {
            Menu {
                ForEach(MuteDuration.allCases, id: \.self) { duration in
                    Button(duration.menuTitle) {
                        viewModel.mute(row, duration: duration)
                    }
                }
            } label: {
                Label("Mute", systemImage: "bell.slash")
            }
        }

        if let url = URL(string: row.communityUrl) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.url = url
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }

        Divider()

        Button(role: .destructive) {
            viewModel.block(row)
        } label: {
            Label("Block Community", systemImage: "hand.raised")
        }
    }
}

extension View {
    /// Attaches the community long-press context menu to a Discover community row.
    func communityContextMenu(for row: CommunityListRow, viewModel: DiscoverViewModel) -> some View {
        contextMenu {
            CommunityContextMenu(row: row, viewModel: viewModel)
        }
    }
}
