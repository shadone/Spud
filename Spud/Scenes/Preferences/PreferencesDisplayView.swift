//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import SwiftUI

/// The Display settings screen for the post list: density (comfortable /
/// compact), thumbnail position (left / right / hidden), and a text-scale
/// override layered on top of Dynamic Type. All apply live — the post list
/// observes the same preference streams and relayouts its cells.
struct PreferencesDisplayView: View {
    let viewModel: PreferencesViewModel

    private var postDensity: Binding<PostDensity> {
        .init { viewModel.postDensity } set: { viewModel.updatePostDensity($0) }
    }

    private var thumbnailPosition: Binding<ThumbnailPosition> {
        .init { viewModel.thumbnailPosition } set: { viewModel.updateThumbnailPosition($0) }
    }

    /// The text-scale slider works in whole points from -3 to +6 relative to
    /// the system body size.
    private var postTextScale: Binding<Double> {
        .init { Double(viewModel.postTextScale) } set: { viewModel.updatePostTextScale(CGFloat($0.rounded())) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Density", selection: postDensity) {
                    ForEach(viewModel.allPostDensities) { density in
                        Label(density.title, systemImage: density.symbolName)
                            .tag(density)
                    }
                }
            } header: {
                Text("Density")
            } footer: {
                Text("Compact fits more posts on screen with tighter spacing.")
            }

            Section {
                Picker("Thumbnail", selection: thumbnailPosition) {
                    ForEach(viewModel.allThumbnailPositions) { position in
                        Label(position.title, systemImage: position.symbolName)
                            .tag(position)
                    }
                }
            } header: {
                Text("Thumbnail")
            } footer: {
                Text("Choose which side the post thumbnail sits on, or hide it entirely.")
            }

            Section {
                Slider(
                    value: postTextScale,
                    in: -3...6,
                    step: 1
                ) {
                    Text("Text Size")
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller")
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger")
                }
            } header: {
                Text("Text Size")
            } footer: {
                Text("Adjusts post text on top of your system Dynamic Type setting.")
            }
        }
        .navigationTitle("Display")
    }
}

#Preview {
    NavigationStack {
        PreferencesDisplayView(viewModel: PreferencesViewModel())
    }
}
