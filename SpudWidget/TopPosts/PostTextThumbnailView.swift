//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import SwiftUI
import WidgetKit

struct PostTextThumbnailView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Design.TextPost.Thumbnail.background.swiftUIColor)
                .frame(width: 40, height: 40)
                .cornerRadius(8)
            Design.TextPost.Thumbnail.icon.swiftUIImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(Design.TextPost.Thumbnail.iconTint.swiftUIColor)
                .frame(width: 24, height: 24)
        }
    }
}

struct PostTextThumbnailView_Previews: PreviewProvider {
    static var previews: some View {
        PostTextThumbnailView()
            .widgetBackground(Color(.systemBackground))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
