//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import SwiftUI

@main
struct MarkdownLabApp: App {
    var body: some Scene {
        WindowGroup { LabView() }
    }
}

private let defaultSample = """
    Valve **finally** shipped SteamOS. Ping @glidergun@lemmy.world or !linux_gaming@lemmy.world. :penguin:

    # Heading
    - one
    - two

    ::: spoiler Numbers
    Locked **60 fps**.
    :::

    Thanks.[^1]

    [^1]: Over a wired connection.
    """

struct LabView: View {
    @State private var source = defaultSample

    private var dump: String {
        BlockTreeDump.lines(MarkdownParser.parse(source)).joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxHeight: 240)
                    .border(.separator)
                Divider()
                ScrollView {
                    Text(dump)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .navigationTitle("MarkdownLab")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
