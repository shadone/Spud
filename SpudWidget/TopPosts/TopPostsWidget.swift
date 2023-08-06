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
                Text("Internal error: Unsupported widget family")

            @unknown default:
                Text("Internal error: Got unknown widget family \(String(describing: family))")
            }
        }
        .padding()
    }
}

struct TopPostsWidget: Widget {
    let kind: String = "TopPostsWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: kind,
            intent: TopPostsConfigurationIntent.self,
            provider: TopPostsProvider(dependencies: DependencyContainer.shared)
        ) { entry in
            TopPostsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Top Posts")
        .description("Displays top posts from your feed.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TopPostsWidget_Previews: PreviewProvider {
    static var previews: some View {
        TopPostsWidgetEntryView(
            entry: TopPostsEntry(
                date: Date(),
                configuration: TopPostsConfigurationIntent(),
                topPosts: .fake,
                images: [:]
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
