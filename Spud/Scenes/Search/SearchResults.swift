//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit

/// A single post result. Carries the server post id so a tap can open
/// PostDetail directly.
struct SearchPostResult: Hashable, Identifiable {
    let serverPostId: Components.Schemas.PostID
    let title: String
    let communityName: String
    let score: Int64
    let numberOfComments: Int64
    let published: Date
    let thumbnailUrl: URL?
    let isNsfw: Bool

    var id: Components.Schemas.PostID {
        serverPostId
    }

    init(
        serverPostId: Components.Schemas.PostID,
        title: String,
        communityName: String,
        score: Int64,
        numberOfComments: Int64,
        published: Date,
        thumbnailUrl: URL?,
        isNsfw: Bool
    ) {
        self.serverPostId = serverPostId
        self.title = title
        self.communityName = communityName
        self.score = score
        self.numberOfComments = numberOfComments
        self.published = published
        self.thumbnailUrl = thumbnailUrl
        self.isNsfw = isNsfw
    }

    init(view: Components.Schemas.PostView) {
        serverPostId = view.post.id
        title = view.post.name
        communityName = view.community.name
        score = view.counts.score
        numberOfComments = view.counts.comments
        published = view.post.published
        thumbnailUrl = view.post.thumbnail_url.flatMap { URL(string: $0) }
        isNsfw = view.post.nsfw
    }
}

/// A single community result. Carries the bare name + home instance so a tap
/// can open the Community screen, and the server id + subscribed state so the
/// inline subscribe button can call `setSubscribed`.
struct SearchCommunityResult: Hashable, Identifiable {
    let serverCommunityId: Components.Schemas.CommunityID
    let name: String
    let qualifiedName: String
    let instance: InstanceActorId
    let subscribersText: String
    let iconUrl: URL?
    let subscribed: Components.Schemas.SubscribedType
    let isNsfw: Bool

    var id: Components.Schemas.CommunityID {
        serverCommunityId
    }

    var isSubscribed: Bool {
        subscribed == .Subscribed
    }

    init(
        serverCommunityId: Components.Schemas.CommunityID,
        name: String,
        qualifiedName: String,
        instance: InstanceActorId,
        subscribersText: String,
        iconUrl: URL?,
        subscribed: Components.Schemas.SubscribedType,
        isNsfw: Bool
    ) {
        self.serverCommunityId = serverCommunityId
        self.name = name
        self.qualifiedName = qualifiedName
        self.instance = instance
        self.subscribersText = subscribersText
        self.iconUrl = iconUrl
        self.subscribed = subscribed
        self.isNsfw = isNsfw
    }

    init?(view: Components.Schemas.CommunityView) {
        let community = view.community
        guard
            let actorUrl = URL(string: community.actor_id),
            let instance = InstanceActorId(from: actorUrl)
        else {
            return nil
        }
        serverCommunityId = community.id
        name = community.name
        qualifiedName = "!\(community.name)@\(instance.hostWithPort)"
        self.instance = instance
        subscribersText = "\(view.counts.subscribers)"
        iconUrl = community.icon.flatMap { URL(string: $0) }
        subscribed = view.subscribed
        isNsfw = community.nsfw
    }
}

/// A single user result. Carries the server person id + home instance so a tap
/// can open the Person screen.
struct SearchUserResult: Hashable, Identifiable {
    let serverPersonId: Components.Schemas.PersonID
    let name: String
    let qualifiedName: String
    let instance: InstanceActorId
    let avatarUrl: URL?

    var id: Components.Schemas.PersonID {
        serverPersonId
    }

    init(
        serverPersonId: Components.Schemas.PersonID,
        name: String,
        qualifiedName: String,
        instance: InstanceActorId,
        avatarUrl: URL?
    ) {
        self.serverPersonId = serverPersonId
        self.name = name
        self.qualifiedName = qualifiedName
        self.instance = instance
        self.avatarUrl = avatarUrl
    }

    init?(view: Components.Schemas.PersonView) {
        let person = view.person
        guard
            let actorUrl = URL(string: person.actor_id),
            let instance = InstanceActorId(from: actorUrl)
        else {
            return nil
        }
        serverPersonId = person.id
        name = person.display_name ?? person.name
        qualifiedName = "@\(person.name)@\(instance.hostWithPort)"
        self.instance = instance
        avatarUrl = person.avatar.flatMap { URL(string: $0) }
    }
}

/// A single comment result. Carries the parent post id so a tap can open the
/// post containing the comment.
struct SearchCommentResult: Hashable, Identifiable {
    let serverCommentId: Components.Schemas.CommentID
    let serverPostId: Components.Schemas.PostID
    let content: String
    let postTitle: String
    let creatorName: String
    let score: Int64
    let published: Date

    var id: Components.Schemas.CommentID {
        serverCommentId
    }

    init(
        serverCommentId: Components.Schemas.CommentID,
        serverPostId: Components.Schemas.PostID,
        content: String,
        postTitle: String,
        creatorName: String,
        score: Int64,
        published: Date
    ) {
        self.serverCommentId = serverCommentId
        self.serverPostId = serverPostId
        self.content = content
        self.postTitle = postTitle
        self.creatorName = creatorName
        self.score = score
        self.published = published
    }

    init(view: Components.Schemas.CommentView) {
        serverCommentId = view.comment.id
        serverPostId = view.post.id
        content = view.comment.content
        postTitle = view.post.name
        creatorName = view.creator.display_name ?? view.creator.name
        score = view.counts.score
        published = view.comment.published
    }
}

/// A single instance result. Sourced client-side from the bundled Lemmy
/// Explorer directory (not federated search). Carries the full
/// ``ExplorerInstanceRecord`` so a tap can open the in-app instance screen
/// directly, the same way the "Open in Spud" instance row does.
struct SearchInstanceResult: Hashable, Identifiable {
    /// Instance host, e.g. "programming.dev". Unique within the directory.
    let baseurl: String
    let name: String
    let usersTotal: Int64
    let iconUrl: URL?
    /// The full directory record, used to open the instance screen on tap.
    let record: ExplorerInstanceRecord

    var id: String {
        baseurl
    }

    /// A short "N members" summary for the cell's secondary line.
    var membersText: String {
        let count = usersTotal.formatted(.number.notation(.compactName))
        return String(
            format: NSLocalizedString(
                "%@ members",
                comment: "Search instance row: member count summary, %@ is a formatted number"
            ),
            count
        )
    }

    init(record: ExplorerInstanceRecord) {
        baseurl = record.baseurl
        name = record.name
        usersTotal = record.usersTotal
        iconUrl = record.iconUrl.flatMap { URL(string: $0) }
        self.record = record
    }

    /// Hashable / Equatable keyed on the unique baseurl: the record is value-stable
    /// for a given baseurl within one search, and ExplorerInstanceRecord is not
    /// itself Hashable.
    static func == (lhs: SearchInstanceResult, rhs: SearchInstanceResult) -> Bool {
        lhs.baseurl == rhs.baseurl
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(baseurl)
    }
}

/// The full set of results for one search response, partitioned by kind. Only
/// the list matching the active scope is shown, but the response can carry
/// more than one kind so all are decoded.
struct SearchResults {
    var posts: [SearchPostResult] = []
    var communities: [SearchCommunityResult] = []
    var users: [SearchUserResult] = []
    var comments: [SearchCommentResult] = []
    /// Client-side Explorer-directory results for the `.instances` scope.
    var instances: [SearchInstanceResult] = []

    init() { }

    init(response: Components.Schemas.SearchResponse) {
        posts = response.posts.map(SearchPostResult.init)
        communities = response.communities.compactMap(SearchCommunityResult.init)
        users = response.users.compactMap(SearchUserResult.init)
        comments = response.comments.map(SearchCommentResult.init)
    }

    /// Returns a copy with NSFW communities and posts removed. Keeps NSFW
    /// content out of search when the user has not opted in (`show_nsfw` off).
    /// Lemmy's search API has no server NSFW filter, so this is client-side.
    func filteringNsfw(_ removeNsfw: Bool) -> SearchResults {
        guard removeNsfw else { return self }
        var copy = self
        copy.posts = posts.filter { !$0.isNsfw }
        copy.communities = communities.filter { !$0.isNsfw }
        return copy
    }

    func isEmpty(for scope: SearchScope) -> Bool {
        switch scope {
        case .posts: posts.isEmpty
        case .communities: communities.isEmpty
        case .users: users.isEmpty
        case .comments: comments.isEmpty
        case .instances: instances.isEmpty
        }
    }
}

/// The phase the search screen is in. Drives which of the designed states the
/// view controller renders.
enum SearchPhase: Equatable {
    /// No query has been entered yet.
    case initial
    /// A query is in flight.
    case loading
    /// Results arrived (possibly empty - the VC distinguishes empty for the
    /// active scope to show the no-results state).
    case loaded
    /// The last search failed.
    case error
}
