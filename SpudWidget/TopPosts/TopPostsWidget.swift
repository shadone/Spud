//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import WidgetKit
import SwiftUI

struct TopPostsWidgetEntryView: View {
    var topPosts: TopPosts
    var images: [URL: UIImage]

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
                ForEach(topPosts.posts.prefix(3)) { post in
                    Link(destination: post.spudUrl) {
                        PostView(post: post, images: images)
                    }
                }

            case .systemLarge:
                Text("Top posts")
                ForEach(topPosts.posts.prefix(6)) { post in
                    Link(destination: post.spudUrl) {
                        PostView(post: post, images: images)
                    }
                }

            case .accessoryInline:
                if let post = topPosts.posts.first {
                    PostAccessoryInlineView(post: post, images: images)
                        .widgetURL(post.spudUrl)
                } else {
                    Text("No data")
                }

            case .accessoryRectangular:
                if let post = topPosts.posts.first {
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

    func makeWidgetConfiguration() -> some WidgetConfiguration {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            return AppIntentConfiguration(
                kind: kind,
                intent: ViewTopPostsAppIntent.self,
                provider: TopPostsAppIntentProvider(dependencies: DependencyContainer.shared)
            ) { entry in
                TopPostsWidgetEntryView(
                    topPosts: entry.topPosts,
                    images: entry.images
                )
            }
        } else {
            return IntentConfiguration(
                kind: kind,
                intent: ViewTopPostsIntent.self,
                provider: TopPostsProvider(dependencies: DependencyContainer.shared)
            ) { entry in
                TopPostsWidgetEntryView(
                    topPosts: entry.topPosts,
                    images: entry.images
                )
            }
        }
    }

    var body: some WidgetConfiguration {
        makeWidgetConfiguration()
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
            topPosts: topPosts,
            images: topPosts.resolveImagesFromAssets
        )
        .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
