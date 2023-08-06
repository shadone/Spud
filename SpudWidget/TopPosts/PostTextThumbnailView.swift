//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI
import WidgetKit

struct PostTextThumbnailView: View {
    @Environment(\.colorScheme) var colorScheme

    var backgroundColor: Color {
        switch colorScheme {
        case .light:
            return Color(white: 0.888)

        case .dark:
            return Color(white: 0.222)

        @unknown default:
            assertionFailure("Got unknown color scheme '\(colorScheme)'")
            return .gray
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(backgroundColor)
                .frame(width: 40, height: 40)
                .cornerRadius(8)
            Image(systemName: "text.justifyleft")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(Color(.lightGray))
                .frame(width: 24, height: 24)
        }
    }
}

struct PostTextThumbnailView_Previews: PreviewProvider {
    static var previews: some View {
        PostTextThumbnailView()
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
