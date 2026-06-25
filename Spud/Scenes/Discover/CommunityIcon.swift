//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI
import UIKit

/// Carries the app's ``ImageServiceType`` down to the Discover SwiftUI views so
/// ``CommunityIcon`` can load real icons. Nil by default, so any view rendered
/// without it (previews, tests) falls back to the letter tile.
private struct ImageServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: ImageServiceType? = nil
}

extension EnvironmentValues {
    var imageService: ImageServiceType? {
        get { self[ImageServiceEnvironmentKey.self] }
        set { self[ImageServiceEnvironmentKey.self] = newValue }
    }
}

/// A community avatar: the real remote icon when one is available and loads,
/// otherwise the deterministic ``CommunityHueIcon`` letter tile. The fetch is
/// self-contained (`.task(id:)` starts it on appear and cancels on disappear or
/// when the URL changes), downsampled to the display size, and reads the image
/// service from the environment so call sites stay terse.
struct CommunityIcon: View {
    let iconUrl: URL?
    let name: String
    let title: String
    var size: CGFloat = 40
    /// When `true`, the icon is obscured with a material overlay clipped to the
    /// same rounded shape. Use for NSFW communities when Blur NSFW is on.
    var isNsfwBlurred: Bool = false

    @Environment(\.imageService) private var imageService
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
            } else {
                CommunityHueIcon(name: name, title: title, size: size)
            }
        }
        .overlay {
            if isNsfwBlurred {
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(.ultraThinMaterial)
            }
        }
        .task(id: iconUrl) {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        image = nil
        guard let iconUrl, let imageService else { return }
        let target = CGSize(width: size * 3, height: size * 3)
        for await state in imageService.fetch(iconUrl, downsampleTo: target) {
            if case let .ready(loaded) = state {
                image = loaded
            }
        }
    }
}
