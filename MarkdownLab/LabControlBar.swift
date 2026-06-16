//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import SpudUIKit
import SwiftUI

/// The live render configuration the Lab toggles.
struct LabConfig: Equatable, Hashable {
    var kind: MarkdownContextKind = .post
    var style: ColorScheme = .light
    var trueBlack = false
    var textScale: CGFloat = 0
    var density: PostDensity = .comfortable
}

struct LabControlBar: View {
    @Binding var config: LabConfig

    var body: some View {
        VStack(spacing: 8) {
            Picker("Context", selection: $config.kind) {
                Text("Post").tag(MarkdownContextKind.post)
                Text("Comment").tag(MarkdownContextKind.comment)
            }.pickerStyle(.segmented)

            HStack {
                Picker("Theme", selection: $config.style) {
                    Text("Light").tag(ColorScheme.light)
                    Text("Dark").tag(ColorScheme.dark)
                }.pickerStyle(.segmented)
                Toggle("OLED", isOn: $config.trueBlack).fixedSize()
            }

            HStack {
                Stepper("Scale \(Int(config.textScale))", value: $config.textScale, in: -3...6)
                Toggle("Compact", isOn: Binding(
                    get: { config.density == .compact },
                    set: { config.density = $0 ? .compact : .comfortable }
                )).fixedSize()
            }
        }
        .font(.footnote)
        .padding(.horizontal)
    }
}
