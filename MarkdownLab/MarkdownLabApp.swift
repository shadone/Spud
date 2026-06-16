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

    ![The Steam Deck OLED on a desk](https://example.com/photos/deck-oled.jpg)

    ![this upload is gone](https://example.com/uploads/broken-pict-rs.png)

    A short clip of the boot chime:

    ![boot chime](https://example.com/media/boot-chime.mp3)

    And the install walkthrough:

    ![install walkthrough](https://example.com/media/walkthrough.mp4)

    | Subsystem | Claimed | Measured |
    |:---|---:|---:|
    | Suspend | < 2s | 1.4s |
    | Battery | 6h | 5h42m |

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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: MarkdownBodyDelegate {
        func markdownBody(didTapLink url: URL) {
            print("[MarkdownLab] link \(url)")
        }

        func markdownBody(didTapImage url: URL, altText: String?, sourceRect: CGRect) {
            print("[MarkdownLab] image \(url) alt=\(altText ?? "-") rect=\(sourceRect)")
        }

        func markdownBody(didTapVideo url: URL) {
            print("[MarkdownLab] video \(url)")
        }

        func markdownBody(didTapAudio url: URL) {
            print("[MarkdownLab] audio \(url)")
        }
    }

    func makeUIView(context: Context) -> MarkdownBodyView {
        let view = MarkdownBodyView(
            context: MarkdownContext(kind: config.kind, textScale: config.textScale, density: config.density)
        )
        view.delegate = context.coordinator
        view.imageLoader = { url in
            // Offline synthetic image; "broken" URLs drive the failed state.
            guard !url.absoluteString.localizedCaseInsensitiveContains("broken") else { return nil }
            return LabImageFactory.placeholder(for: url)
        }
        view.setBlocks(MarkdownParser.parse(source))
        return view
    }

    func updateUIView(_ uiView: MarkdownBodyView, context: Context) {
        uiView.delegate = context.coordinator
        uiView.setBlocks(MarkdownParser.parse(source))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownBodyView, context _: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        let height = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return CGSize(width: width, height: height)
    }
}
