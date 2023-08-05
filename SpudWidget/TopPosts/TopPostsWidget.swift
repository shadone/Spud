//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import WidgetKit
import SwiftUI

struct TopPostsWidgetEntryView: View {
    var entry: TopPostsProvider.Entry

    @Environment(\.widgetFamily) var family

    @State var numberOfPosts = 3

    var body: some View {
        VStack(alignment: .leading) {
            switch family {
            case .systemMedium:
                ForEach(entry.topPosts.posts.prefix(3)) { post in
                    Link(destination: post.spudUrl) {
                        PostView(post: post, images: entry.images)
                    }
                }

            case .systemLarge:
                Text("Top posts")
                ForEach(entry.topPosts.posts.prefix(6)) { post in
                    Link(destination: post.spudUrl) {
                        PostView(post: post, images: entry.images)
                    }
                }

            case .systemSmall, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline:
                fatalError("Unsupported widget family")

            @unknown default:
                fatalError("Got unknown widget family \(family)")
            }
        }
        .padding()
    }
}

struct TopPostsWidget: Widget {
    let kind: String = "TopPostsWidget"

    // TODO: look into fetching images using background request
    // https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension
    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: kind,
            intent: ConfigurationIntent.self,
            provider: TopPostsProvider()
        ) { entry in
            TopPostsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Top Posts")
        .description("This is an example widget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TopPostsWidget_Previews: PreviewProvider {
    static var previews: some View {
        TopPostsWidgetEntryView(
            entry: TopPostsEntry(
                date: Date(),
                configuration: ConfigurationIntent(),
                topPosts: .fake,
                images: [:]
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
