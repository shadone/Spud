//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI

struct PreferencesPostMarkingAndHidingView: View {
    @State var markPostsRead: Bool = true
    @State var markPostsReadOnScroll: Bool = false

    enum AutoHidePostsType {
        case permanently
        case untilNewComments
    }

    @State var autoHidePosts: AutoHidePostsType = .permanently
    @State var autoHidePostsInCommunities: Bool = false

    var body: some View {
        Form {
            // TODO: implement the logic behind this view
            Text("TODO: these settings are not implemented yet")

            Section {
                VStack(alignment: .leading) {
                    Toggle("Mark Posts as Read", isOn: $markPostsRead)
                    Text("The posts that are interacted with are marked as read, for example posts that are opened or upvoted.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                VStack(alignment: .leading) {
                    Toggle("Mark as Read on Scrolling", isOn: $markPostsReadOnScroll)
                    Text("Automatically mark as read all posts that are shown in the list.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            } header: {
                Text("Posts")
            }

            Section {
                Picker("Hide posts…", selection: $autoHidePosts) {
                    Text("Permanently").tag(AutoHidePostsType.permanently)
                    Text("Until new comments").tag(AutoHidePostsType.untilNewComments)
                }

                Toggle("Auto Hide in Communities", isOn: $autoHidePostsInCommunities)
            } header: {
                Text("Auto Hide")
            } footer: {
                switch autoHidePosts {
                case .permanently:
                    Text("Automatically hides read posts.")
                case .untilNewComments:
                    Text("Automatically hides read posts until new comments are added.")
                }
            }
        }
        .navigationTitle("Post Marking & Hiding")
    }
}

struct PreferencesPostMarkingAndHidingView_Preview: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PreferencesPostMarkingAndHidingView()
        }
    }
}
