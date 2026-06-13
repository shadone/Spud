//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import SwiftUI

/// Lists the account's hidden posts and muted communities, each with
/// swipe-to-restore (unhide / unmute). Shown from Settings; both lists read
/// from the local store on appear.
struct PreferencesHiddenAndMutedView: View {
    let viewModel: HiddenAndMutedViewModel

    var body: some View {
        List {
            Section("Hidden Posts") {
                if viewModel.hiddenPosts.isEmpty {
                    Text("Posts you hide appear here. Swipe to unhide.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.hiddenPosts) { post in
                        HiddenPostRow(post: post)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    viewModel.unhide(post: post)
                                } label: {
                                    Label("Unhide", systemImage: "eye")
                                }
                                .tint(.accentColor)
                            }
                    }
                }
            }

            Section("Muted Communities") {
                if viewModel.mutedCommunities.isEmpty {
                    Text("Communities you mute appear here. Swipe to unmute.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.mutedCommunities) { community in
                        MutedCommunityRow(community: community)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    viewModel.unmute(community: community)
                                } label: {
                                    Label("Unmute", systemImage: "bell")
                                }
                                .tint(.accentColor)
                            }
                    }
                }
            }
        }
        .navigationTitle("Hidden & Muted")
        .onAppear { viewModel.load() }
    }
}

/// A hidden post: title plus the community it came from, with an optional
/// thumbnail.
private struct HiddenPostRow: View {
    let post: HiddenPostListItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: post.thumbnailUrl.flatMap { URL(string: $0) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "doc.text.image")
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.body)
                    .lineLimit(2)
                Text(post.communityName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A muted community: its `!name@instance` handle plus when the mute lifts.
private struct MutedCommunityRow: View {
    let community: MutedCommunityListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.handle(forActorId: community.communityActorId))
                .font(.body)
            Text(Self.expiryText(community.mutedUntil))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Builds "!name@instance" from a community actor id like
    /// "https://lemmy.world/c/world".
    static func handle(forActorId actorId: String) -> String {
        guard
            let url = URL(string: actorId),
            let host = url.host
        else { return actorId }
        let name = url.lastPathComponent
        return name.isEmpty ? "!\(host)" : "!\(name)@\(host)"
    }

    static func expiryText(_ mutedUntil: Date?) -> String {
        guard let mutedUntil else {
            return NSLocalizedString("Muted until you unmute", comment: "Indefinite mute description")
        }
        let formatted = mutedUntil.formatted(.relative(presentation: .named))
        return String(
            format: NSLocalizedString("Muted, lifts %@", comment: "Timed mute description; %@ is a relative time like 'in 3 days'"),
            formatted
        )
    }
}
