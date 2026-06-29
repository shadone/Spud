//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SwiftUI
import UIKit

/// A circular person avatar: the real remote image when one is available and
/// loads, otherwise a deterministic hue tile with the person's initial. Reads
/// the image service from the environment (`\.imageService`) so it falls back to
/// the hue tile in previews / tests where no service is injected.
struct ProfileAvatarView: View {
    let avatarUrl: URL?
    /// Used for the deterministic hue and the initial in the fallback tile.
    let name: String
    var size: CGFloat = 60

    @Environment(\.imageService) private var imageService
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ProfileHueAvatar(name: name, size: size)
            }
        }
        .task(id: avatarUrl) {
            await loadAvatar()
        }
    }

    private func loadAvatar() async {
        image = nil
        guard let avatarUrl, let imageService else { return }
        let target = CGSize(width: size * 3, height: size * 3)
        for await state in imageService.fetch(avatarUrl, downsampleTo: target) {
            if case let .ready(loaded) = state {
                image = loaded
            }
        }
    }
}

/// The deterministic letter-tile fallback for ``ProfileAvatarView``: a filled
/// circle whose hue is derived from the name, with the name's initial centered.
struct ProfileHueAvatar: View {
    let name: String
    var size: CGFloat = 60

    var body: some View {
        Circle()
            .fill(Color(hue: hue / 360, saturation: 0.5, brightness: 0.6))
            .frame(width: size, height: size)
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var letter: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }

    /// DJB2 hash over the name, matched to the Discover community hue so avatars
    /// look consistent app-wide.
    private var hue: Double {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Double(hash % 360)
    }
}
