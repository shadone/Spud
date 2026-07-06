//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit
import SwiftUI

struct PostAccessoryRectangularView: View {
    @State var post: Post

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(post.title)
                    .font(.system(size: 12))
                    .fontWeight(.medium)

                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(verbatim: post.community.name)
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    Text("\(Image(systemName: "arrow.up"))\(CountFormatter.string(post.score))")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text("\(Image(systemName: "text.bubble"))\(CountFormatter.string(post.numberOfComments))")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
        }
    }
}
