//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import SpudUIKit
import SwiftUI

@main
struct MarkdownLabApp: App {
    var body: some Scene {
        WindowGroup { LabView() }
    }
}

private let defaultSample = """
    Valve **finally** shipped SteamOS. Ping @glidergun@lemmy.world or !linux_gaming@lemmy.world.

    - A USB-C drive, **8 GB or larger**.
        - Save files sync via cloud.
        - Screenshot your BIOS first.
    - The official `rufus` flasher.

    1. Disable Secure Boot.
    2. Flash the recovery image.

    | Subsystem | Claimed | Measured |
    |:---|---:|---:|
    | Suspend | < 2s | 1.4s |
    | Battery | 6h | 5h42m |

    ```bash
    export ALSA_CARD=acp
    pactl set-sink-volume @DEFAULT_SINK@ 140%
    ```

    > Third-party support is **best-effort**.

    ::: spoiler Benchmarks
    Locked **60 fps** at 800p medium.
    :::

    Thanks for reading.[^1]

    [^1]: Re-download over a wired connection if the checksum fails.
    """

struct LabView: View {
    @State private var source = defaultSample
    @State private var config = LabConfig()

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $source)
                .font(.system(.footnote, design: .monospaced))
                .frame(height: 150)
                .border(.separator)
            LabControlBar(config: $config)
                .padding(.vertical, 6)
            Divider()
            ScrollView {
                MarkdownBodyHost(source: source, config: config)
                    .id(config)
                    .padding(16)
            }
        }
        .preferredColorScheme(config.style)
    }
}

/// Hosts the UIKit `MarkdownBodyView`. The context is baked at init from
/// `config`; `LabView` keys this host on `config` so a toggle change recreates
/// it. `updateUIView` handles live source edits.
struct MarkdownBodyHost: UIViewRepresentable {
    let source: String
    let config: LabConfig

    func makeUIView(context _: Context) -> MarkdownBodyView {
        let view = MarkdownBodyView(
            context: MarkdownContext(kind: config.kind, textScale: config.textScale, density: config.density)
        )
        view.setBlocks(MarkdownParser.parse(source))
        return view
    }

    func updateUIView(_ uiView: MarkdownBodyView, context _: Context) {
        uiView.setBlocks(MarkdownParser.parse(source))
    }
}
