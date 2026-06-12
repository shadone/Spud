//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI

/// Lists the account's blocked users with swipe-to-unblock. Block lists are
/// fetched from the server on appear; an empty state is shown when there are
/// none.
struct PreferencesBlockedUsersView: View {
    let viewModel: BlockedListViewModel

    var body: some View {
        List {
            switch viewModel.phase {
            case .loading where viewModel.persons.isEmpty:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)

            case .error where viewModel.persons.isEmpty:
                ContentUnavailableView(
                    "Couldn't load blocked users",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Pull to refresh to try again.")
                )

            default:
                if viewModel.persons.isEmpty {
                    ContentUnavailableView(
                        "No blocked users",
                        systemImage: "hand.raised",
                        description: Text("Users you block won't appear in your feeds.")
                    )
                } else {
                    ForEach(viewModel.persons) { person in
                        BlockedRow(title: person.name, subtitle: person.handle, iconUrl: person.avatarUrl)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.unblock(person: person)
                                } label: {
                                    Label("Unblock", systemImage: "hand.raised.slash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .refreshable { viewModel.load() }
        .onAppear { viewModel.load() }
    }
}

/// Lists the account's blocked communities with swipe-to-unblock.
struct PreferencesBlockedCommunitiesView: View {
    let viewModel: BlockedListViewModel

    var body: some View {
        List {
            switch viewModel.phase {
            case .loading where viewModel.communities.isEmpty:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)

            case .error where viewModel.communities.isEmpty:
                ContentUnavailableView(
                    "Couldn't load blocked communities",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Pull to refresh to try again.")
                )

            default:
                if viewModel.communities.isEmpty {
                    ContentUnavailableView(
                        "No blocked communities",
                        systemImage: "hand.raised",
                        description: Text("Communities you block won't appear in your feeds.")
                    )
                } else {
                    ForEach(viewModel.communities) { community in
                        BlockedRow(title: community.name, subtitle: community.handle, iconUrl: community.iconUrl)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.unblock(community: community)
                                } label: {
                                    Label("Unblock", systemImage: "hand.raised.slash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Blocked Communities")
        .refreshable { viewModel.load() }
        .onAppear { viewModel.load() }
    }
}

/// A single blocked-entity row: name + federated handle, with an optional
/// avatar/icon thumbnail.
private struct BlockedRow: View {
    let title: String
    let subtitle: String
    let iconUrl: URL?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: iconUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
