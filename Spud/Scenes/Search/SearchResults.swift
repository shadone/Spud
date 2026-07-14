//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit

/// A single post result. Carries the full feed ``PostListRow`` built from the
/// network `PostView`, so a searched post renders through the exact same rich
/// feed cell (`community@instance`, counts, thumbnail, status/author badges, NSFW
/// blur) — plus the author line the feed omits. The server post id (for opening
/// PostDetail on tap) and the title / NSFW flag are exposed off the row.
struct SearchPostResult: Hashable, Identifiable {
    /// The feed row the shared post cell renders from. Author-status, counts,
    /// thumbnail, NSFW, vote/save/read, and moderation flags all ride along.
    let row: PostListRow

    /// Hashable / Equatable identity keyed on the unique server post id: a search
    /// response never repeats a post, and the list is replaced wholesale on each
    /// query, so identity alone is the right diffable key.
    var id: Int64 {
        row.serverPostId
    }

    /// Server post id for the tap-to-PostDetail navigation. Narrowed to `Lemmy.PostID`
    /// (`Int32`) with the trapping initializer, matching every other `Int64 -> PostID`
    /// site in the app — Lemmy's wire post id is already `Int32`, so this never traps.
    var serverPostId: Lemmy.PostID {
        Lemmy.PostID(row.serverPostId)
    }

    /// The post title. Retained for URL-suggestion / accessibility callers.
    var title: String {
        row.title
    }

    /// Whether the post (or its community) is NSFW. Drives the cell's blur when the
    /// post is *kept* (Show-NSFW on). When Show-NSFW is off the post is dropped from
    /// search entirely (see ``SearchResults/filteringNsfw(_:)``), matching the feed.
    var isNsfw: Bool {
        row.isNsfw
    }

    init(row: PostListRow) {
        self.row = row
    }

    init(view: Lemmy.PostView) {
        self.init(row: PostListRow(view: view))
    }

    static func == (lhs: SearchPostResult, rhs: SearchPostResult) -> Bool {
        lhs.row.serverPostId == rhs.row.serverPostId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(row.serverPostId)
    }
}

/// A single community result. Carries the bare name + home instance so a tap
/// can open the Community screen, and the server id + subscribed state so the
/// inline subscribe button can call `setSubscribed`.
struct SearchCommunityResult: Hashable, Identifiable {
    let serverCommunityId: Lemmy.CommunityID
    let name: String
    let qualifiedName: String
    let instance: InstanceActorId
    let subscribersText: String
    let iconUrl: URL?
    let followState: FollowState
    let isNsfw: Bool
    /// The community's federation actor id (e.g.
    /// `https://lemmy.world/c/tincidunt`). Used as the client-local mute-database
    /// key (mirrors `CommunityListRow.communityUrl`) and as the Share / Copy Link
    /// destination in the long-press context menu.
    let communityUrl: String

    var id: Lemmy.CommunityID {
        serverCommunityId
    }

    init(
        serverCommunityId: Lemmy.CommunityID,
        name: String,
        qualifiedName: String,
        instance: InstanceActorId,
        subscribersText: String,
        iconUrl: URL?,
        followState: FollowState,
        isNsfw: Bool,
        communityUrl: String
    ) {
        self.serverCommunityId = serverCommunityId
        self.name = name
        self.qualifiedName = qualifiedName
        self.instance = instance
        self.subscribersText = subscribersText
        self.iconUrl = iconUrl
        self.followState = followState
        self.isNsfw = isNsfw
        self.communityUrl = communityUrl
    }

    init?(view: Lemmy.CommunityView) {
        let community = view.community
        guard
            let actorUrl = URL(string: community.apId),
            let instance = InstanceActorId(from: actorUrl)
        else {
            return nil
        }
        serverCommunityId = Lemmy.CommunityID(community.id)
        name = community.name
        qualifiedName = "!\(community.name)@\(instance.hostWithPort)"
        self.instance = instance
        subscribersText = "\(community.subscribers)"
        iconUrl = community.iconUrl.flatMap { URL(string: $0) }
        followState = view.followState
        isNsfw = community.nsfw
        communityUrl = community.apId
    }
}

/// A single user result. Carries the server person id + home instance so a tap
/// can open the Person screen.
///
/// This carries no per-viewer block state: the search `Lemmy.PersonView` has
/// no per-viewer block flag (Lemmy's search API doesn't return one), and
/// unlike a community's client-local mute state, whether the viewer has
/// blocked a person is only knowable via a network round trip
/// (`LemmyService.fetchBlockedList`, backed by `getSite` -- the same source
/// `PersonViewController`'s block menu resolves from on appear). The
/// long-press context menu (`UserContextMenuBuilder`) can't afford that fetch
/// at menu-build time, so `SearchViewController` always builds it with
/// `isBlocked: false`, which only ever offers "Block user" (never "Unblock")
/// from Search -- the person's own profile screen shows the real state.
struct SearchUserResult: Hashable, Identifiable {
    let serverPersonId: Lemmy.PersonID
    let name: String
    let qualifiedName: String
    let instance: InstanceActorId
    let avatarUrl: URL?

    var id: Lemmy.PersonID {
        serverPersonId
    }

    init(
        serverPersonId: Lemmy.PersonID,
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

    init?(view: Lemmy.PersonView) {
        let person = view.person
        guard
            let actorUrl = URL(string: person.apId),
            let instance = InstanceActorId(from: actorUrl)
        else {
            return nil
        }
        serverPersonId = Lemmy.PersonID(person.id)
        name = person.displayName ?? person.name
        qualifiedName = "@\(person.name)@\(instance.hostWithPort)"
        self.instance = instance
        avatarUrl = person.avatarUrl.flatMap { URL(string: $0) }
    }
}

/// A single comment result. Carries the parent post id so a tap can open the
/// post containing the comment, plus the enrichment the long-press context
/// menu needs (creator identity, saved state) mirroring
/// `PostDetailViewController`'s comment context-menu actions.
struct SearchCommentResult: Hashable, Identifiable {
    let serverCommentId: Lemmy.CommentID
    let serverPostId: Lemmy.PostID
    let content: String
    let postTitle: String
    let creatorName: String
    let score: Int64
    let published: Date
    /// The comment creator's server person id, for the "View author" context-menu action.
    let creatorPersonId: Lemmy.PersonID
    /// The creator's federation actor id (e.g. `https://lemmy.world/u/alice`), resolved
    /// into an `InstanceActorId` for `pushPerson`.
    let creatorActorId: String?
    /// The comment's own federated ActivityPub id (`comment.ap_id`). Used to build the
    /// canonical Share / Copy Link URL exactly like
    /// `PostDetailViewController.shareComment` does (`LinkURL.forComment`), falling back
    /// to `<instance>/comment/<id>` when nil.
    let originalCommentUrl: String?
    /// Whether the signed-in viewer has saved the comment. Drives the Save/Unsave label
    /// in the long-press context menu.
    let isSaved: Bool

    var id: Lemmy.CommentID {
        serverCommentId
    }

    init(
        serverCommentId: Lemmy.CommentID,
        serverPostId: Lemmy.PostID,
        content: String,
        postTitle: String,
        creatorName: String,
        score: Int64,
        published: Date,
        creatorPersonId: Lemmy.PersonID,
        creatorActorId: String?,
        originalCommentUrl: String?,
        isSaved: Bool
    ) {
        self.serverCommentId = serverCommentId
        self.serverPostId = serverPostId
        self.content = content
        self.postTitle = postTitle
        self.creatorName = creatorName
        self.score = score
        self.published = published
        self.creatorPersonId = creatorPersonId
        self.creatorActorId = creatorActorId
        self.originalCommentUrl = originalCommentUrl
        self.isSaved = isSaved
    }

    init(view: Lemmy.CommentView) {
        serverCommentId = Lemmy.CommentID(view.comment.id)
        serverPostId = Lemmy.PostID(view.post.id)
        content = view.comment.content
        postTitle = view.post.name
        creatorName = view.creator.displayName ?? view.creator.name
        score = view.comment.score
        published = view.comment.publishedAt
        creatorPersonId = Lemmy.PersonID(view.creator.id)
        creatorActorId = view.creator.apId
        originalCommentUrl = view.comment.apId
        isSaved = view.isSaved
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
        let count = CountFormatter.string(usersTotal)
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

    init(response: LemmyKit.SearchResults) {
        posts = response.posts.map(SearchPostResult.init)
        communities = response.communities.compactMap(SearchCommunityResult.init)
        users = response.persons.compactMap(SearchUserResult.init)
        comments = response.comments.map(SearchCommentResult.init)
    }

    /// Returns a copy with NSFW *posts and communities* removed when the user has not
    /// opted in (`show_nsfw` off, so `removeNsfw` is true). Lemmy's search API has no
    /// server NSFW filter, so this is client-side.
    ///
    /// This mirrors the feed's NSFW policy exactly. The feed only *shows* NSFW posts
    /// when Show-NSFW is on (then blurs each per the blur preference); with Show-NSFW
    /// off the server filters them out entirely. Search realizes the same policy
    /// client-side:
    /// - **Show-NSFW off** (`removeNsfw` true): drop NSFW posts *and* communities —
    ///   respect the opt-out, never render NSFW to a user who turned it off.
    /// - **Show-NSFW on** (`removeNsfw` false): keep NSFW posts; the shared feed cell
    ///   blurs them per the `blurNsfw` preference (with tap-to-reveal). Communities are
    ///   kept too — the community cell has no blur affordance, but the user opted in.
    ///
    /// Non-NSFW content is never dropped.
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
