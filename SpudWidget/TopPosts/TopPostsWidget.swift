//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI
import WidgetKit

struct TopPostsWidgetEntryView: View {
    var topPosts: TopPosts
    var images: [URL: UIImage]

    @Environment(\.widgetFamily) var family

    var shouldAddBackground: Bool {
        switch family {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular:
            if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
                // It is mandatory to have content background in iOS 17 or else
                // a warning is displayed in place of the widget.
                return true
            }
            return false
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            return true
        @unknown default:
            return true
        }
    }

    var padding: EdgeInsets {
        switch family {
        case .systemSmall:
            return .init(top: 0, leading: 0, bottom: 0, trailing: 0)

        case .systemMedium, .systemLarge, .systemExtraLarge:
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

            case .systemSmall:
                ForEach(topPosts.posts.prefix(3)) { post in
                    Link(destination: post.spudUrl) {
                        PostViewSmall(post: post, images: images)
                    }
                }

            case .systemExtraLarge, .accessoryCircular:
                Text("Internal error: Unsupported widget family")

            @unknown default:
                Text("Internal error: Got unknown widget family \(String(describing: family))")
            }
        }
        .padding(padding)
        .if(shouldAddBackground) { view in
            view.widgetBackground(Color(.systemBackground))
        }
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
                .systemSmall,
                .systemMedium,
                .systemLarge,
                .accessoryInline,
                .accessoryRectangular,
            ])
    }
}

@available(iOS 17, *)
#Preview("large", as: WidgetFamily.systemLarge) {
    TopPostsWidget()
} timeline: {
    TopPostsEntry(
        date: Date(),
        topPosts: TopPosts.snapshot,
        images: TopPosts.snapshot.resolveImagesFromAssets
    )
}

@available(iOS 17, *)
#Preview("medium", as: WidgetFamily.systemMedium) {
    TopPostsWidget()
} timeline: {
    TopPostsEntry(
        date: Date(),
        topPosts: TopPosts.snapshot,
        images: TopPosts.snapshot.resolveImagesFromAssets
    )
}

@available(iOS 17, *)
#Preview("small", as: WidgetFamily.systemSmall) {
    TopPostsWidget()
} timeline: {
    TopPostsEntry(
        date: Date(),
        topPosts: TopPosts.snapshot,
        images: TopPosts.snapshot.resolveImagesFromAssets
    )
}

// Old school preview that could be useful for testing on iOS 16
struct TopPostsWidget_Previews: PreviewProvider {
    static var topPosts = TopPosts.snapshot

    static var previews: some View {
        TopPostsWidgetEntryView(
            topPosts: topPosts,
            images: topPosts.resolveImagesFromAssets
        )
        .previewDisplayName("old preview for iOS 16")
        .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
