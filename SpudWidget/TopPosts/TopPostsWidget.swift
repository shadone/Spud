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

    var padding: EdgeInsets {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            return .init(top: 16, leading: 16, bottom: 16, trailing: 16)

        case .accessoryCircular, .accessoryInline, .accessoryRectangular:
            return .init(top: 0, leading: 0, bottom: 0, trailing: 0)

        @unknown default:
            return .init()
        }
    }

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

            case .accessoryInline:
                if let post = entry.topPosts.posts.first {
                    PostAccessoryInlineView(post: post, images: entry.images)
                        .widgetURL(post.spudUrl)
                } else {
                    Text("No data")
                }

            case .accessoryRectangular:
                if let post = entry.topPosts.posts.first {
                    PostAccessoryRectangularView(post: post)
                        .widgetURL(post.spudUrl)
                } else {
                    Text("No data")
                }


            case .systemSmall, .systemExtraLarge, .accessoryCircular:
                Text("Internal error: Unsupported widget family")

            @unknown default:
                Text("Internal error: Got unknown widget family \(String(describing: family))")
            }
        }
        .padding(padding)
    }
}

struct TopPostsWidget: Widget {
    let kind: String = "TopPostsWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: kind,
            intent: ViewTopPostsIntent.self,
            provider: TopPostsProvider(dependencies: DependencyContainer.shared)
        ) { entry in
            TopPostsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Top Posts")
        .description("Displays top posts from your feed.")
        .supportedFamilies([
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct TopPostsWidget_Previews: PreviewProvider {
    static var topPosts = TopPosts.snapshot

    static var previews: some View {
        TopPostsWidgetEntryView(
            entry: TopPostsEntry(
                date: Date(),
                configuration: ViewTopPostsIntent(),
                topPosts: topPosts,
                images: topPosts.resolveImagesFromAssets
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
