//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI

/// Renders a Post as AccessoryInline widget family.
/// This is a special family that only allows text and optional image. This is only used on Apple Watch complications.
struct PostAccessoryInlineView: View {
    @State var post: Post
    @State var images: [URL: UIImage]

    var text: String {
        let score = UpvotesFormatter.string(from: post.score)
        return "\(post.title) ↑\(score)"
    }

    var body: some View {
        Text(text)

        if case let .image(thumbnailUrl) = post.type {
            if let image = images[thumbnailUrl] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 12, height: 21, alignment: .center)
            }
        }
    }
}
