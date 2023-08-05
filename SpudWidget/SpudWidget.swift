//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import WidgetKit
import SwiftUI
import Intents
import SpudDataKit
import UIKit

struct DependencyContainer:
    HasAccountService,
    HasSiteService,
    HasImageService,
    HasAlertService
{
    let dataStore: DataStoreType = DataStore()
    let accountService: AccountServiceType
    let siteService: SiteServiceType
    let imageService: ImageServiceType
    let alertService: AlertServiceType = AlertService()

    init() {
        imageService = ImageService(alertService: alertService)
        siteService = SiteService(dataStore: dataStore)
        accountService = AccountService(
            siteService: siteService,
            dataStore: dataStore
        )

        start()
    }

    private func start() {
        dataStore.startService()
        siteService.startService()
    }
}

class Provider: IntentTimelineProvider {
    typealias Entry = SimpleEntry

    let dependencies = DependencyContainer()

    var disposables = Set<AnyCancellable>()

    // MARK: Functions

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationIntent(),
            topPosts: .placeholder,
            images: [:]
        )
    }

    func getSnapshot(
        for configuration: ConfigurationIntent,
        in context: Context,
        completion: @escaping (SimpleEntry) -> ()
    ) {
        let now = Date()
        let entry = SimpleEntry(
            date: now,
            configuration: configuration,
            topPosts: .placeholder, // TODO:
            images: [:]
        )
        completion(entry)
    }

    func getTimeline(
        for configuration: ConfigurationIntent,
        in context: Context,
        completion: @escaping (Timeline<Entry>) -> ()
    ) {
        Task {
            let feed = await fetchFeed()

            let postInfos = feed.pages
                .sorted(by: { $0.index < $1.index })
                .first?
                .pageElements
                .sorted(by: { $0.index < $1.index })
                .map(\.post)
                .compactMap(\.postInfo)
                // The max number of posts widget of any size might need.
                .prefix(6) ?? []

            let topPosts = TopPosts(
                posts: postInfos
                    .map { postInfo -> Post in
                        let postType: Post.PostType
                        if let thumbnailUrl = postInfo.thumbnailUrl {
                            postType = .image(thumbnailUrl)
                        } else {
                            postType = .text
                        }

                        let postUrl = URL.SpudInternalLink.post(
                            postId: postInfo.post.postId,
                            instance: postInfo.post.account.site.instance.actorId
                        ).url

                        let community: Community
                        if let communityInfo = postInfo.community.communityInfo {
                            community = Community(
                                name: communityInfo.name,
                                site: communityInfo.hostnameFromActorId
                            )
                        } else {
                            community = Community(name: "-", site: "")
                        }

                        return .init(
                            spudUrl: postUrl,
                            title: postInfo.title,
                            type: postType,
                            community: community,
                            score: postInfo.score,
                            numberOfComments: postInfo.numberOfComments
                        )
                    }
            )

            let imageUrls = topPosts.posts
                .compactMap { $0.type.imageUrl }

            let imagesByUrl = await withTaskGroup(of: (URL, UIImage?).self) { group in
                for url in imageUrls {
                    group.addTask {
                        await (url, self.fetchImage(url))
                    }
                }
                return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
            }

            let now = Date()

            let entry = SimpleEntry(
                date: now,
                configuration: configuration,
                topPosts: topPosts,
                images: imagesByUrl
            )

            let inOneHour = now.addingTimeInterval(60 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(inOneHour))
            completion(timeline)
        }
    }

    @MainActor func fetchFeed() async -> LemmyFeed {
        let account = dependencies.accountService.defaultAccount()
        let lemmyService = dependencies.accountService
            .lemmyService(for: account)

        let feed = lemmyService
            .createFeed(.frontpage(listingType: .all, sortType: .hot))

        do {
            try await lemmyService
                .fetchFeed(feedId: feed.objectID, page: nil)
                .async()
        } catch {
            print("### Failed to fetch feed: \(error)")
        }

        self.dependencies.dataStore
            .mainContext
            .refresh(feed, mergeChanges: true)

        return feed
    }

    @MainActor private func fetchImage(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        return UIImage(data: data)?
            // We have to scale down the images as large images cannot be serialized by WidgetKit:
            // "Widget archival failed due to image being too large [3] - (4000, 3000)."
            .scalePreservingAspectRatio(targetSize: .init(width: 40, height: 40))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent

    let topPosts: TopPosts
    let images: [URL: UIImage]
}

struct PostView: View {
    @State var post: Post
    @State var images: [URL: UIImage]

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(post.title)
                    .font(.system(size: 14))
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack {
                    HStack(spacing: 0) {
                        Text(verbatim: post.community.name)
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Text(verbatim: "@\(post.community.site)")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 10))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    Text("\(Image(systemName: "arrow.up"))\(UpvotesFormatter.string(from: post.score))")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text("\(Image(systemName: "text.bubble"))\(CommentsFormatter.string(from: post.numberOfComments))")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }

            Spacer()

            switch post.type {
            case .text:
                ZStack {
                    Rectangle()
                        .fill(Color(white: 0.888))
                        .frame(width: 40, height: 40)
                        .cornerRadius(8)
                    Image(systemName: "text.justifyleft")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(Color(.lightGray))
                        .frame(width: 24, height: 24)
                }

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

struct SpudWidgetEntryView: View {
    var entry: Provider.Entry

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

struct SpudWidget: Widget {
    let kind: String = "SpudWidget"

    // TODO: look into fetching images using background request
    // https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension
    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: kind,
            intent: ConfigurationIntent.self,
            provider: Provider()
        ) { entry in
            SpudWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Top Posts")
        .description("This is an example widget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SpudWidget_Previews: PreviewProvider {
    static var previews: some View {
        SpudWidgetEntryView(
            entry: SimpleEntry(
                date: Date(),
                configuration: ConfigurationIntent(),
                topPosts: .fake,
                images: [:]
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
