//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI

struct PostViewSmall: View {
    @State var post: Post
    @State var images: [URL: UIImage]

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(post.title)
                    .font(.system(size: 10))
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 2) {
                    Text(verbatim: post.community.name)
                        .foregroundColor(.secondary)
                        .font(.system(size: 8))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text("\(Image(systemName: "arrow.up"))\(UpvotesFormatter.string(from: post.score))")
                        .foregroundColor(.secondary)
                        .font(.system(size: 8))
                        .lineLimit(1)
                    Text("\(Image(systemName: "text.bubble"))\(CommentsFormatter.string(from: post.numberOfComments))")
                        .foregroundColor(.secondary)
                        .font(.system(size: 8))
                        .lineLimit(1)
                }
            }

            Spacer()

            switch post.type {
            case .text:
                PostTextThumbnailView()

            case let .image(thumbnailUrl):
                if let image = images[thumbnailUrl] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(.gray)
                        .frame(width: 40, height: 40)
                        .cornerRadius(8)
                }
            }
        }
    }
}
