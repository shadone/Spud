//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.lemmyService

public enum LemmyServiceError: Error {
    case internalInconsistency(description: String)

    /// A low level API error has occurred.
    case apiError(LemmyApiError)

    /// The operation requires a signed-in account, but this service is
    /// backed by a signed-out account.
    case requiresAuthentication

    /// The content we were asked to send is malformed or un-sendable (a
    /// programmer/data error, e.g. a direct-message row with no recipient).
    /// `OutboxFailureClass` classifies this as `.permanent` so the outbox parks
    /// the row as `.failed` (content kept) instead of retrying forever — there
    /// is no network round-trip that could ever make invalid content valid.
    case invalidContent(description: String)

    /// The account's home instance does not support this operation (e.g. it
    /// runs Lemmy 1.0, whose v3 compat shim lacks the endpoint — see
    /// `InstanceCapabilities`). Thrown BEFORE any network call as the
    /// service-level backstop behind the UI capability gates; classified
    /// permanent by `OutboxFailureClass` (retrying cannot help until Spud
    /// itself speaks the instance's newer API).
    case unsupportedByInstance(InstanceCapability)

    init(from error: Error) {
        if let error = error as? LemmyApiError {
            self = .apiError(error)
        } else {
            assertionFailure("Unexpected exception \(type(of: error)): \(error))")
            self = .internalInconsistency(description: "Unexpected exception \(type(of: error)): \(error))")
        }
    }
}

public protocol LemmyServiceType: Actor {
    /// Fetch one page of posts for `feed`. Pass `pageCursor: nil` for the
    /// first page; on subsequent calls pass the cursor returned by the
    /// previous fetch. `showNsfw` is forwarded to the server's `getPosts`
    /// request param, so the NSFW filtering is server-side (applies to
    /// signed-out accounts too). Returns the cursor for the next page, or nil
    /// if the feed is exhausted.
    @discardableResult
    func fetchFeed(_ feed: FeedHandle, pageCursor: String?, showNsfw: Bool) async throws -> String?

    func fetchComments(
        serverPostId: Lemmy.PostID,
        sortType: Lemmy.CommentSortType
    ) async throws

    func fetchSiteInfo() async throws

    /// Fetch the instance's site info via the version-neutral `getSiteNeutral()`
    /// and return it, mirroring it into the database exactly like ``fetchSiteInfo()``
    /// does. The neutral ``LemmyKit/SiteInfo`` is handed back so the caller can read
    /// the instance's identity / stats directly (used to open the in-app instance
    /// screen for an arbitrary host that isn't in the Explorer directory). A
    /// successful return doubles as the Lemmy-API-compatibility test for the host.
    @discardableResult
    func getSiteInfo() async throws -> LemmyKit.SiteInfo

    /// Push the account's `show_nsfw` preference to the server via
    /// `saveUserSettings`, then mirror the new value onto the local account
    /// row so the cached `AccountRecord.showNsfw` stays in sync. Requires a
    /// signed-in account: a signed-out account is a silent no-op (the local
    /// client preference still governs feed filtering via the request param).
    func setShowNsfw(_ showNsfw: Bool) async throws

    /// Push the account's `blur_nsfw` preference to the server via
    /// `saveUserSettings`, then mirror the new value onto the local account
    /// row so the cached `AccountRecord.blurNsfw` stays in sync. Requires a
    /// signed-in account: a signed-out account is a silent no-op (blur is a
    /// pure client-side render concern there).
    func setBlurNsfw(_ blurNsfw: Bool) async throws

    /// Push the account's default post sort to the server via `saveUserSettings`
    /// so the choice follows the account across devices. The local
    /// `AccountRecord.defaultSortType` is written separately (and synchronously)
    /// by `AccountServiceType.setDefaultSortType(_:forAccountKeychainId:)` — which
    /// also persists it for signed-out accounts — so this only mirrors the value
    /// up to the server. A signed-out account is a silent no-op.
    func setDefaultSortType(_ sortType: Lemmy.SortType) async throws

    /// Push the signed-in account's editable profile (display name, bio, avatar,
    /// banner) and synced preference flags (show scores / bot accounts / read
    /// posts / others' avatars, default feed) to the server, then mirror the new
    /// values onto the local `PersonRecord` / `AccountRecord` so the cached
    /// profile stays in sync. Requires a signed-in account: a signed-out account
    /// throws `LemmyServiceError.requiresAuthentication` (unlike the
    /// single-setting setters, there is no local-only fallback for a profile
    /// edit). `displayName` / `bio` may be empty to clear the field on the server.
    /// `avatar` / `banner` are `ProfileImageEdit`s: `.unchanged` leaves the image
    /// alone, `.set(imageData:…)` uploads a new one, `.removed` clears it — the
    /// image push (via the dedicated neutral avatar/banner endpoints) runs before
    /// the text settings, so a push failure surfaces the same way a settings-push
    /// failure does, with nothing mirrored to roll back.
    func saveProfile(
        displayName: String?,
        bio: String?,
        avatar: ProfileImageEdit,
        banner: ProfileImageEdit,
        showScores: Bool,
        showBotAccounts: Bool,
        showReadPosts: Bool,
        showAvatars: Bool,
        defaultListingType: Lemmy.ListingType
    ) async throws

    func fetchPersonInfo(
        serverPersonId: Lemmy.PersonID
    ) async throws

    /// Fetch a person's profile together with one page of their posts and
    /// comments. The `person_view` is mirrored into the database (so the
    /// profile header can be observed like any other person), while the posts
    /// and comments are returned transiently - a snapshot of the requested
    /// page rather than rows in a persistent feed, mirroring how `search`
    /// returns its results. Navigation from a result uses the server-side ids
    /// carried in the response, which the id-based screens resolve on their
    /// own. Works for both signed-in and signed-out accounts.
    func fetchPersonContent(
        serverPersonId: Lemmy.PersonID,
        sort: Lemmy.SortType,
        page: Int64
    ) async throws -> PersonContentPage

    /// Fetch the full community info (header fields, counts, subscribed state)
    /// for `serverCommunityId` and mirror it into the database. Used to
    /// populate the community screen for communities the account hasn't cached.
    func fetchCommunityInfo(
        serverCommunityId: Lemmy.CommunityID
    ) async throws

    /// Fetch the full community info by name (`gnome` for a local community or
    /// `worldnews@lemmy.world` for a remote one) and mirror it into the
    /// database. Returns the resolved server-side community id.
    @discardableResult
    func fetchCommunityInfo(
        communityName: String
    ) async throws -> Lemmy.CommunityID

    /// Run a search against the backing instance and return the decoded
    /// results. Search results are transient (a snapshot of what matched the
    /// query right now), so they are returned directly rather than mirrored
    /// into the persistent feed. Navigation from a result uses the server-side
    /// ids carried in the response, which the id-based screens resolve on
    /// their own. Works for both signed-in and signed-out accounts.
    func search(
        query: String,
        type: Lemmy.SearchType,
        sort: Lemmy.SortType,
        listingType: Lemmy.ListingType,
        page: Int64
    ) async throws -> LemmyKit.SearchResults

    /// List communities on the backing instance via `/api/v3/community/list`
    /// and return the decoded `CommunityView`s. Like `search`, the results are
    /// transient (a live snapshot) and are NOT mirrored into the persistent
    /// feed. Used to populate the in-app instance screen with the instance's
    /// own communities when the bundled Explorer directory has none (e.g. a
    /// remote/synthesized instance resolved live via `/api/v3/site`). Works for
    /// both signed-in and signed-out accounts.
    func listCommunities(
        type: Lemmy.ListingType,
        sort: Lemmy.SortType?,
        limit: Int64?
    ) async throws -> [Lemmy.CommunityView]

    /// Subscribe to or unsubscribe from `serverCommunityId` for the backing
    /// account. Flips the community's `subscribedState` (to `.pending` /
    /// `.notSubscribed`) and the `accountFollowedCommunity` junction
    /// optimistically, then enqueues the change to the idempotent mutation
    /// outbox for durable, retried delivery — the UI reflects the new state
    /// instantly, and the outbox's authoritative post-send mirror later
    /// reconciles it to the server's actual answer (e.g. `.subscribed` rather
    /// than `.pending`, for communities that require approval). Throws
    /// `LemmyServiceError.requiresAuthentication` if this service is backed by
    /// a signed-out account.
    func setSubscribed(
        serverCommunityId: Lemmy.CommunityID,
        subscribed: Bool
    ) async throws

    func vote(
        serverPostId: Lemmy.PostID,
        vote action: VoteStatus.Action
    ) async throws

    func vote(
        serverCommentId: Lemmy.CommentID,
        vote action: VoteStatus.Action
    ) async throws

    /// Create a new comment on `serverPostId`. Pass `parentCommentId` to
    /// reply to an existing comment, or `nil` to reply to the post itself.
    /// Throws `LemmyServiceError.requiresAuthentication` if this service is
    /// backed by a signed-out account.
    func createComment(
        serverPostId: Lemmy.PostID,
        content: String,
        parentCommentId: Lemmy.CommentID?
    ) async throws

    /// Create a new post in `serverCommunityId` and mirror the returned
    /// `PostView` into the persistent store so it shows up immediately.
    /// Returns the new post's server id for navigation. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    @discardableResult
    func createPost(
        serverCommunityId: Lemmy.CommunityID,
        name: String,
        url: String?,
        body: String?,
        nsfw: Bool
    ) async throws -> Lemmy.PostID

    /// Upload an image to the backing instance's pict-rs and return the
    /// fully-qualified image url. Transient (not mirrored). Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func uploadImage(
        imageData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> URL

    /// Save or unsave `serverPostId` for the backing account. Throws
    /// `LemmyServiceError.requiresAuthentication` if this service is backed
    /// by a signed-out account.
    func setSaved(
        serverPostId: Lemmy.PostID,
        saved: Bool
    ) async throws

    /// Save or unsave `serverCommentId` for the backing account. Throws
    /// `LemmyServiceError.requiresAuthentication` if this service is backed
    /// by a signed-out account.
    func setSaved(
        serverCommentId: Lemmy.CommentID,
        saved: Bool
    ) async throws

    /// Delete or restore `serverCommentId` — the user's OWN comment. Flips the
    /// comment's `isDeleted` state optimistically, enqueues the change to the
    /// idempotent mutation outbox, and rolls back on permanent failure (exactly
    /// like hide). Throws `LemmyServiceError.requiresAuthentication` if this
    /// service is backed by a signed-out account.
    func deleteComment(
        serverCommentId: Lemmy.CommentID,
        deleted: Bool
    ) async throws

    /// Delete or restore `serverPostId` — the user's OWN post. Flips the post's
    /// `isDeleted` state optimistically, enqueues the change to the idempotent
    /// mutation outbox, and rolls back on permanent failure (exactly like the
    /// comment delete). Throws `LemmyServiceError.requiresAuthentication` if this
    /// service is backed by a signed-out account.
    func deletePost(
        serverPostId: Lemmy.PostID,
        deleted: Bool
    ) async throws

    func fetchPostInfo(
        serverPostId: Lemmy.PostID
    ) async throws

    /// Hide or unhide `serverPostId` for the backing account. Hidden posts are
    /// dropped from feed lists. Throws `LemmyServiceError.requiresAuthentication`
    /// if this service is backed by a signed-out account.
    func hidePost(
        serverPostId: Lemmy.PostID,
        hidden: Bool
    ) async throws

    /// A stream of permanent outbox failures (e.g. an expired session) for the
    /// vote/save/hide operations enqueued through this service. Each event names
    /// the entity whose optimistic write was rolled back so the UI can surface
    /// the failure. Transient failures (offline / server hiccups) are retried
    /// silently and never appear here.
    func outboxFailureEvents() async -> AsyncStream<OutboxFailure>

    /// Drains any operations persisted in this account's outbox right now (e.g.
    /// ops left pending by a previous session, or held while offline). Lazily
    /// constructs and `start()`s the outbox if needed. A no-op when the account
    /// row can't be resolved.
    func drainPendingOutbox() async

    // MARK: Composer outbox

    /// Persist a draft (or overwrite an existing one with the same `draftKey`)
    /// and return the `clientToken` that identifies this composition through its
    /// lifecycle. Throws when the account row can't be resolved.
    func saveDraft(_ input: OutboundDraftInput) async throws -> String

    /// Hand the draft identified by `clientToken` to the `ComposerOutboxService`
    /// for immediate delivery. A no-op when the composer outbox can't be built.
    func submitDraft(clientToken: String) async

    /// Retry a previously failed composition identified by `clientToken`.
    func retryComposition(clientToken: String) async

    /// Permanently discard the composition identified by `clientToken`.
    func discardComposition(clientToken: String) async

    /// Load a previously saved draft by its `draftKey`. Returns `nil` when the
    /// draft can't be found or when the account row can't be resolved.
    func loadDraft(draftKey: String) async throws -> OutboundContentRecord?

    /// Persist (or overwrite) the single per-recipient DM autosave draft — the
    /// unsent in-progress message text for `recipientServerPersonId` — and return
    /// its `clientToken`. There is one draft row per correspondent (keyed by
    /// `dmDraftKey`); this does NOT send. Throws when the account row can't be
    /// resolved.
    func saveDirectMessageDraft(
        body: String,
        recipientServerPersonId: Int64
    ) async throws -> String

    /// Durably + optimistically send a private message to
    /// `recipientServerPersonId`. Creates a uniquely-keyed `.directMessage`
    /// outbound row at `.queued` status, then hands it to the
    /// `ComposerOutboxService`, which enqueues and drains on a detached task —
    /// this method returns immediately after the fast DB write (it never awaits
    /// the network send) so the optimistic bubble appears instantly. Returns the
    /// `clientToken` so the UI can correlate the optimistic bubble with its
    /// eventual success/failure. Throws when the account row can't be resolved.
    @discardableResult
    func sendDirectMessage(
        body: String,
        recipientServerPersonId: Int64
    ) async throws -> String

    /// Apply an edit's title/body/url/nsfw to the user's OWN post optimistically,
    /// so the open post header reflects the edit immediately. The change is scoped
    /// to the backing account's post row; the content outbox subsequently sends the
    /// `editPost` and the post-edit reconcile guard keeps the optimistic values
    /// from being clobbered by a refresh until the server confirms. A no-op when
    /// the account row can't be resolved.
    func applyOptimisticPostEdit(
        serverPostId: Lemmy.PostID,
        title: String,
        body: String?,
        url: String?,
        nsfw: Bool
    ) async

    /// A stream of permanent composer failures for compositions enqueued through
    /// this service. Terminates immediately (empty stream) when the composer
    /// outbox can't be built.
    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure>

    /// A stream of composer successes for compositions delivered through this
    /// service. Terminates immediately (empty stream) when the composer outbox
    /// can't be built.
    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess>

    func markAsRead(
        serverPostId: Lemmy.PostID
    ) async throws

    // MARK: Inbox

    /// Fetch one page of inbox replies as version-neutral
    /// ``InboxCommentNotification``s. Results are transient (returned to the
    /// caller, like `search`) rather than mirrored into the persistent store.
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    func fetchReplies(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> [InboxCommentNotification]

    /// Fetch one page of inbox mentions as version-neutral
    /// ``InboxCommentNotification``s. Transient, like `fetchReplies`.
    func fetchMentions(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> [InboxCommentNotification]

    /// Fetch one cursor-delimited page of private messages, returning the mapped
    /// messages plus the opaque cursor for the next page (nil at the end of the
    /// listing). Transient, like `fetchReplies`. Sourced from the version-neutral,
    /// cursor-paginated private-message list, each message paired with its read
    /// state. Pass `nil` for `pageCursor` to fetch the first page; feed a returned
    /// `nextCursor` back in to load the next.
    func fetchPrivateMessages(
        unreadOnly: Bool,
        pageCursor: String?
    ) async throws -> (messages: [IncomingPrivateMessage], nextCursor: String?)

    /// Fetch the count of unread replies, mentions, and private messages.
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    func unreadCount() async throws -> UnreadCount

    /// Mark a single comment-based inbox item (reply or mention) read/unread. The
    /// ``InboxItemReadReference`` carries the id from the fetch that produced the
    /// item and routes to the endpoint matching its originating backend.
    func markInboxItemAsRead(
        reference: InboxItemReadReference,
        read: Bool
    ) async throws

    /// Mark a single private message as read/unread.
    func markPrivateMessageAsRead(
        privateMessageId: Lemmy.PrivateMessageID,
        read: Bool
    ) async throws

    /// Mark all inbox items (replies + mentions + private messages) as read.
    func markAllInboxAsRead() async throws

    /// Send a private message to `recipientId` and return the created view.
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    @discardableResult
    func sendPrivateMessage(
        content: String,
        recipientId: Lemmy.PersonID
    ) async throws -> Lemmy.PrivateMessageView

    // MARK: Safety (block / report)

    /// Block or unblock the person `serverPersonId` for the backing account.
    /// On success the returned `PersonView` is mirrored into the store; the
    /// server filters blocked authors out of subsequent feed fetches, so the
    /// caller should refresh the current feed to make blocked content
    /// disappear. Throws `LemmyServiceError.requiresAuthentication` when signed
    /// out.
    func setBlocked(
        serverPersonId: Lemmy.PersonID,
        blocked: Bool
    ) async throws

    /// Block or unblock the community `serverCommunityId` for the backing
    /// account. On success the returned `CommunityView` is mirrored into the
    /// store; the server filters blocked communities out of subsequent feed
    /// fetches, so the caller should refresh the current feed. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func setBlocked(
        serverCommunityId: Lemmy.CommunityID,
        blocked: Bool
    ) async throws

    /// Report `serverPostId` with the given `reason`. Transient (not mirrored).
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    func reportPost(
        serverPostId: Lemmy.PostID,
        reason: String
    ) async throws

    /// Report `serverCommentId` with the given `reason`. Transient (not
    /// mirrored). Throws `LemmyServiceError.requiresAuthentication` when signed
    /// out.
    func reportComment(
        serverCommentId: Lemmy.CommentID,
        reason: String
    ) async throws

    /// Fetch the account's current block lists from the server (via
    /// `getSite` → `my_user`). Transient (returned to the caller, like
    /// `search`) so the settings screen always reflects server truth. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func fetchBlockedList() async throws -> BlockedList

    // MARK: Moderation

    /// Fetch the account's moderation capability from the server (via
    /// `getSite` → `my_user`): the set of communities it moderates plus
    /// whether it is a site admin. Transient (returned to the caller, like
    /// `fetchBlockedList`), so mod UI always reflects server truth. A
    /// signed-out account resolves to `.none` rather than throwing, so the
    /// caller can gate UI uniformly without branching on auth state.
    func fetchModerationCapability() async throws -> ModerationCapability

    /// Remove (or restore) `serverPostId` as a moderator/admin. On success the
    /// updated `PostView` is mirrored into the store. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func removePost(
        serverPostId: Lemmy.PostID,
        removed: Bool,
        reason: String?
    ) async throws

    /// Lock (or unlock) `serverPostId` as a moderator/admin. Mirrors the
    /// updated `PostView`. Throws `.requiresAuthentication` when signed out.
    func lockPost(
        serverPostId: Lemmy.PostID,
        locked: Bool
    ) async throws

    /// Feature (pin) or unfeature `serverPostId`. `local` pins to the instance
    /// front page (admin-only); otherwise pins to the community. Mirrors the
    /// updated `PostView`. Throws `.requiresAuthentication` when signed out.
    func featurePost(
        serverPostId: Lemmy.PostID,
        featured: Bool,
        local: Bool
    ) async throws

    /// Remove (or restore) `serverCommentId` as a moderator/admin. Mirrors the
    /// updated `CommentView`. Throws `.requiresAuthentication` when signed out.
    func removeComment(
        serverCommentId: Lemmy.CommentID,
        removed: Bool,
        reason: String?
    ) async throws

    /// Distinguish (or undistinguish) `serverCommentId`. Mirrors the updated
    /// `CommentView`. Throws `.requiresAuthentication` when signed out.
    func distinguishComment(
        serverCommentId: Lemmy.CommentID,
        distinguished: Bool
    ) async throws

    /// Ban (or unban) `serverPersonId` from `serverCommunityId`. When banning,
    /// `removeData` also removes the person's existing content in the
    /// community. Mirrors the updated `PersonView`. Transient otherwise. Throws
    /// `.requiresAuthentication` when signed out.
    func banFromCommunity(
        serverCommunityId: Lemmy.CommunityID,
        serverPersonId: Lemmy.PersonID,
        ban: Bool,
        removeData: Bool,
        reason: String?
    ) async throws

    /// Resolves a federated object (post, community, person, or comment) by its
    /// canonical URL, under this service's account. Comments resolve to
    /// `.comment` (deferred); unrecognised input resolves to `.unresolved`.
    func resolveObject(query: String) async throws -> ResolvedLemmyObject
}

/// One page of a person's authored content, split by kind. Replaces the raw
/// `GetPersonDetailsResponse` the person screens used to read: the neutral
/// surface serves a person's profile (`personDetailsNeutral`) separately from a
/// paged, interleaved post/comment feed (`personContentNeutral`), so this carries
/// just the transient content page (the profile is mirrored into the store). A
/// small Sendable value type so it can flow from the actor to the main-actor UI.
public struct PersonContentPage: Sendable, Equatable {
    /// The posts on this page, newest first.
    public let posts: [Lemmy.PostView]
    /// The comments on this page, newest first.
    public let comments: [Lemmy.CommentView]

    public init(posts: [Lemmy.PostView], comments: [Lemmy.CommentView]) {
        self.posts = posts
        self.comments = comments
    }
}

/// The current account's moderation capability, decoded from `getSite` →
/// `my_user`: the communities it moderates and whether it is a site admin. A
/// small Sendable value type so it can flow from the `LemmyService` actor to
/// the main-actor UI that gates mod controls.
public struct ModerationCapability: Sendable, Equatable {
    /// Server-side ids of the communities the account moderates.
    public let moderatedCommunityIds: Set<Lemmy.CommunityID>
    /// Whether the account is a site admin (can moderate anywhere and feature
    /// posts to the instance front page).
    public let isAdmin: Bool

    public init(
        moderatedCommunityIds: Set<Lemmy.CommunityID>,
        isAdmin: Bool
    ) {
        self.moderatedCommunityIds = moderatedCommunityIds
        self.isAdmin = isAdmin
    }

    /// No moderation powers. The resolved capability for a signed-out account
    /// or an account that moderates nothing and is not an admin.
    public static let none = ModerationCapability(moderatedCommunityIds: [], isAdmin: false)

    /// Whether the account can take moderator actions in `communityId` -
    /// either because it moderates that community or because it is a site
    /// admin (admins can moderate everywhere).
    public func canModerate(communityId: Lemmy.CommunityID) -> Bool {
        isAdmin || moderatedCommunityIds.contains(communityId)
    }

    /// Whether any moderation surface should be offered at all.
    public var hasAnyPower: Bool {
        isAdmin || !moderatedCommunityIds.isEmpty
    }
}

/// The account's current block lists, decoded from `getSite` → `my_user`.
/// A small Sendable value type so it can flow from the `LemmyService` actor to
/// the main-actor settings screen.
public struct BlockedList: Sendable, Equatable {
    public struct Person: Sendable, Equatable, Identifiable {
        public let serverPersonId: Lemmy.PersonID
        public let name: String
        /// `@user@instance`-style handle for display.
        public let handle: String
        public let avatarUrl: URL?

        public var id: Lemmy.PersonID {
            serverPersonId
        }
    }

    public struct Community: Sendable, Equatable, Identifiable {
        public let serverCommunityId: Lemmy.CommunityID
        public let name: String
        /// `community@instance`-style handle for display.
        public let handle: String
        public let iconUrl: URL?

        public var id: Lemmy.CommunityID {
            serverCommunityId
        }
    }

    public let persons: [Person]
    public let communities: [Community]

    public init(persons: [Person], communities: [Community]) {
        self.persons = persons
        self.communities = communities
    }

    public static let empty = BlockedList(persons: [], communities: [])
}

/// The count of unread inbox items, split by kind. A small Sendable value type
/// so it can flow from the `LemmyService` actor to the main-actor badge.
public struct UnreadCount: Sendable, Equatable {
    public let replies: Int
    public let mentions: Int
    public let privateMessages: Int
    /// Total unread across all kinds; drives the tab badge. Stored (not derived)
    /// because a v4 instance reports only a combined total with no per-kind
    /// breakdown, so `total` can exceed `replies + mentions + privateMessages`
    /// (which are all zero there) — read `total`, never re-sum the per-kind
    /// fields.
    public let total: Int

    /// Full init. `total` is independent of the per-kind fields so a v4-backed
    /// count (a combined total with no breakdown) is representable.
    public init(replies: Int, mentions: Int, privateMessages: Int, total: Int) {
        self.replies = replies
        self.mentions = mentions
        self.privateMessages = privateMessages
        self.total = total
    }

    /// Per-kind init (the v3 shape): `total` is the sum of the three kinds.
    public init(replies: Int, mentions: Int, privateMessages: Int) {
        self.init(
            replies: replies,
            mentions: mentions,
            privateMessages: privateMessages,
            total: replies + mentions + privateMessages
        )
    }

    /// Combined-total init (the v4 shape): the per-kind breakdown is unavailable,
    /// so the three per-kind fields are zero and only `total` carries the count.
    public init(total: Int) {
        self.init(replies: 0, mentions: 0, privateMessages: 0, total: total)
    }

    public static let zero = UnreadCount(replies: 0, mentions: 0, privateMessages: 0)
}

public actor LemmyService: LemmyServiceType {
    // MARK: Public

    let accountIdentifierForLogging: String

    // MARK: Private

    let accountIsSignedOut: Bool
    let appDatabase: AppDatabase
    let api: LemmyApi
    // internal: shared with LemmyService+Composer
    let reachability: ReachabilityMonitoring

    /// Dual-sink recorder for structured diagnostic events (OSLog + GRDB).
    /// Injectable so tests can pass a `DiagnosticLogSpy` without database I/O.
    let diagnostics: DiagnosticLogging

    /// Task-memoized lazy outbox. Construction is deferred to the first
    /// vote/save/hide call because it needs `accountSiteIds()` (an async DB
    /// read) and must call `start()`. Memoizing the *Task* (not the value)
    /// makes concurrent callers share one construction even under actor
    /// reentrancy: the `outboxTask = task` assignment runs before the first
    /// `await task.value`, so a second caller arriving mid-await sees the
    /// in-flight task rather than starting a second drain loop.
    private var outboxTask: Task<OutboxService?, Never>?

    /// Task-memoized lazy composer outbox. Same construction pattern as
    /// `outboxTask` — see that property's comment for rationale.
    // internal: shared with LemmyService+Composer
    var composerOutboxTask: Task<ComposerOutboxService?, Never>?

    // MARK: Functions

    init(
        accountKeychainId: String,
        accountIsSignedOut: Bool,
        appDatabase: AppDatabase,
        api: LemmyApi,
        reachability: ReachabilityMonitoring,
        diagnostics: DiagnosticLogging? = nil
    ) {
        accountIdentifierForLogging = accountKeychainId
        self.accountIsSignedOut = accountIsSignedOut
        self.appDatabase = appDatabase
        self.api = api
        self.reachability = reachability
        self.diagnostics = diagnostics ?? DiagnosticLog(appDatabase: appDatabase)

        logger.info("Creating new service for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
    }

    /// Resolves the instance HOST string (e.g. `lemmy.world`) for the account
    /// backing this service. Returns `nil` when the account row hasn't been
    /// mirrored yet — callers must treat `nil` as "unknown, emit without tag"
    /// rather than blocking on it.
    // internal: shared with LemmyService+Safety, LemmyService+Composer
    func resolveInstanceHost() async -> String? {
        let rawActorId = await appDatabase.accountInstanceActorId(forKeychainId: accountIdentifierForLogging)
        return rawActorId.flatMap { InstanceActorId(from: $0) }?.hostWithPort
    }

    /// The home instance's capability set, derived per call from the persisted
    /// site version (fail-open on nil — see `InstanceCapabilities`).
    // internal: shared with LemmyService+Inbox, LemmyService+Composer, LemmyService+Safety
    func instanceCapabilities() async -> InstanceCapabilities {
        let version = await appDatabase.accountSiteVersion(forKeychainId: accountIdentifierForLogging)
        return InstanceCapabilities.capabilities(
            software: .lemmy,
            version: version.flatMap(LemmyVersion.init(parsing:))
        )
    }

    /// Backstop gate: throws `LemmyServiceError.unsupportedByInstance` (and
    /// records a diagnostic event) when the home instance can't serve
    /// `capability`. Call at the top of every gated operation, before any
    /// network or outbox work.
    // internal: shared with LemmyService+Inbox, LemmyService+Composer, LemmyService+Safety
    func requireCapability(_ capability: InstanceCapability) async throws {
        guard await instanceCapabilities().can(capability) else {
            await recordCapabilityBlocked(capability)
            throw LemmyServiceError.unsupportedByInstance(capability)
        }
    }

    /// Records the shared `capability.blocked` diagnostic event — used both by
    /// `requireCapability`'s throwing gate and by the soft-degrade setters
    /// (`setShowNsfw`/`setBlurNsfw`/`setDefaultSortType`) that skip the server
    /// push without throwing (this event is their only trace of the skip).
    func recordCapabilityBlocked(_ capability: InstanceCapability) async {
        // Info level (not error): this is an expected, UI-gated condition on
        // older instances, not a failure — the durable log just makes it
        // observable in About → Logs.
        await diagnostics.record(
            category: .site,
            level: .info,
            event: "capability.blocked",
            message: "Instance does not support \(capability.rawValue)",
            instance: api.instanceHostname,
            metadata: ["capability": capability.rawValue]
        )
    }

    /// Lazily builds (and `start()`s) the per-account `OutboxService`, returning
    /// `nil` only when the account row can't be resolved (no ids -> no outbox).
    /// Memoized via `outboxTask` so every call shares one service instance.
    // internal: shared with LemmyService+Safety
    func outboxService() async -> OutboxService? {
        if let outboxTask { return await outboxTask.value }
        let task = Task<OutboxService?, Never> { [self] in
            guard let ids = try? await accountSiteIds() else { return nil }
            let performer = LemmyOutboxPerformer(
                api: api,
                appDatabase: appDatabase,
                accountId: ids.0,
                siteId: ids.1
            )
            // A nil result (account not yet mirrored) is acceptable — events are
            // emitted without an instance tag rather than blocking outbox construction.
            let instanceHost = await resolveInstanceHost()
            let service = OutboxService(
                accountId: ids.0,
                appDatabase: appDatabase,
                performer: performer,
                reachability: reachability,
                now: { Date().timeIntervalSince1970 },
                diagnostics: DiagnosticLog(appDatabase: appDatabase),
                instance: instanceHost
            )
            await service.start()
            return service
        }
        outboxTask = task
        let result = await task.value
        if result == nil { outboxTask = nil } // allow retry after a transient failure; keep memoized only on success
        return result
    }

    /// Looks up the GRDB account row for this LemmyService and returns
    /// `(accountRowId, siteRowId)` - both are needed as foreign keys when
    /// upserting posts/comments/communities.
    func accountSiteIds() async throws -> (Int64, Int64)? {
        try await appDatabase.writer.read { db in
            guard
                let account = try AccountRecord
                .filter(Column("accountKeychainId") == self.accountIdentifierForLogging)
                .fetchOne(db)
            else {
                return nil
            }
            return (account.id!, account.siteId)
        }
    }

    public func fetchFeed(_ feed: FeedHandle, pageCursor: String?, showNsfw: Bool) async throws -> String? {
        let feedKey = feed.feedKey
        let feedType = feed.feedType

        // The neutral `getPostsNeutral` takes an opaque `Cursor`; Spud persists the
        // cursor as a bare string, so bridge in both directions.
        let cursor = pageCursor.map { Cursor(rawValue: $0) }

        let page: Page<Lemmy.PostView>
        do {
            switch feedType {
            case let .frontpage(listingType, sortType):
                logger.debug("""
                    Fetch feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feedKey, privacy: .public) \
                    listingType=\(listingType.rawValue, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    showNsfw=\(showNsfw, privacy: .public) \
                    pageCursor=\(pageCursor ?? "nil", privacy: .public)
                    """)
                // Filter NSFW server-side via `show_nsfw` (matches v4, which
                // filters by the account setting): `showNsfw` carries the client's
                // synced show-NSFW preference, so it applies to signed-out accounts
                // too. NSFW posts that ARE returned are still blurred by the
                // account's blur setting — this only gates server-side inclusion.
                let (sort, timeRange) = sortType.neutralPostSort
                page = try await api.getPostsNeutral(
                    listingType: listingType,
                    sort: sort,
                    timeRange: timeRange,
                    showNsfw: showNsfw,
                    pageCursor: cursor
                )

            case let .community(communityName, instance, sortType):
                logger.debug("""
                    Fetch feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feedKey, privacy: .public) \
                    communityName=\(communityName, privacy: .public) \
                    instance=\(instance.debugDescription, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    showNsfw=\(showNsfw, privacy: .public) \
                    pageCursor=\(pageCursor ?? "nil", privacy: .public)
                    """)
                // `getPostsNeutral` scopes a community by id, not by name, so resolve
                // (and cache) the community's server id first.
                let communityId = try await resolveCommunityServerId(
                    name: communityName,
                    instance: instance
                )
                let (sort, timeRange) = sortType.neutralPostSort
                page = try await api.getPostsNeutral(
                    listingType: .All,
                    sort: sort,
                    communityId: Int64(communityId),
                    timeRange: timeRange,
                    showNsfw: showNsfw,
                    pageCursor: cursor
                )

            case let .saved(sortType):
                guard !accountIsSignedOut else {
                    throw LemmyServiceError.requiresAuthentication
                }
                logger.debug("""
                    Fetch saved feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feedKey, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    showNsfw=\(showNsfw, privacy: .public) \
                    pageCursor=\(pageCursor ?? "nil", privacy: .public)
                    """)
                // Thread the user's chosen sort so the saved feed honours it.
                // Documented as v3-only: v4's `ListPersonSaved` has no sort param,
                // so on v4 this is a no-op and the server's default order is used.
                // `getSavedPostsNeutral` has no `show_nsfw` param, so NSFW posts
                // that come back are blurred (never hidden) by the account's blur
                // setting — a saved-feed-only gap, not a general client-side
                // NSFW filter.
                let (sort, timeRange) = sortType.neutralPostSort
                page = try await api.getSavedPostsNeutral(
                    sort: sort,
                    timeRange: timeRange,
                    pageCursor: cursor
                )
            }
        } catch let error as LemmyServiceError {
            throw error
        } catch {
            logger.error("""
                Fetch feed failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                feedId=\(feedKey, privacy: .public) \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch feed complete with \(page.items.count, privacy: .public) posts. \
            account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            feedId=\(feedKey, privacy: .public)
            """)

        try await mirrorFeedPageToAppDatabase(
            feedKey: feedKey,
            feedType: feedType,
            posts: page.items
        )

        return page.nextPage?.rawValue
    }

    /// Resolves the server-side id of the community named `name` (`gnome` for a
    /// local community, or `worldnews@lemmy.world` for a remote one) at `instance`,
    /// preferring the cached row and falling back to a network fetch+mirror. Needed
    /// because `getPostsNeutral` scopes a community by id, not by name.
    private func resolveCommunityServerId(
        name: String,
        instance: InstanceActorId
    ) async throws -> Lemmy.CommunityID {
        // The community's own federation actor id is `<instance>/c/<local-name>`.
        let localName = name.split(separator: "@").first.map(String.init) ?? name
        let actorId = "\(instance.actorId)/c/\(localName)"
        if let (accountRowId, _) = try? await accountSiteIds(),
           let cached = appDatabase.communityServerIdSync(forAccountId: accountRowId, actorId: actorId)
        {
            return Lemmy.CommunityID(cached)
        }
        // Not cached — fetch+mirror by fully-qualified name so a remote community
        // resolves against ITS home instance, not the account's.
        let qualifiedName = "\(localName)@\(instance.hostWithPort)"
        return try await fetchCommunityInfo(communityName: qualifiedName)
    }

    private func mirrorFeedPageToAppDatabase(
        feedKey: String,
        feedType: FeedType,
        posts: [Lemmy.PostView]
    ) async throws {
        guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(
                description: "Feed page not persisted: no account/site row for keychainId"
            )
        }
        try await appDatabase.appendFeedPage(
            feedKey: feedKey,
            feedType: feedType,
            accountId: accountRowId,
            siteId: siteRowId,
            posts: posts
        )
    }

    public func fetchComments(
        serverPostId: Lemmy.PostID,
        sortType: Lemmy.CommentSortType
    ) async throws {
        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
            postId=\(serverPostId, privacy: .public) \
            sortType=\(sortType.rawValue, privacy: .public)
            """)

        let page: Page<Lemmy.CommentView>
        do {
            page = try await api.getCommentsNeutral(
                postId: Int64(serverPostId),
                sort: sortType.neutralCommentSort
            )
        } catch {
            logger.error("""
                Fetch comments failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            if ContentNotFound.matchesPost(error) {
                try? await appDatabase.markPostUnavailable(
                    forKeychainId: accountIdentifierForLogging,
                    serverPostId: Int64(serverPostId)
                )
            }
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            complete with \(page.items.count, privacy: .public) comments
            """)

        try await mirrorCommentsToAppDatabase(
            serverPostId: serverPostId,
            sortType: sortType,
            comments: page.items
        )

        // A removed comment carries no reason in the comment object — fetch it
        // from the public modlog, but only when there's something to explain.
        if page.items.contains(where: \.comment.removed) {
            await mirrorCommentRemovalReasons(serverPostId: serverPostId)
        }
    }

    /// Fetches moderator removal reasons for the post's removed comments from
    /// the public modlog and mirrors them. Best-effort: a failure here must not
    /// break comment loading.
    private func mirrorCommentRemovalReasons(serverPostId: Lemmy.PostID) async {
        do {
            guard let (accountRowId, _) = try await accountSiteIds() else { return }

            let modlog = try await api.getModlog(
                postID: serverPostId,
                type: .ModRemoveComment
            )
            let reasons = Self.removalReasons(from: modlog.removed_comments)

            try await appDatabase.mirrorCommentRemovalReasons(
                forServerPostId: Int64(serverPostId),
                accountId: accountRowId,
                reasonsByServerCommentId: reasons
            )
        } catch {
            logger.error("Fetch comment removal reasons failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Builds a `serverCommentId -> reason` map from modlog comment-removal
    /// entries. The modlog is newest-first, so the first entry seen per comment
    /// is the most recent removal; restores (`removed == false`) and empty
    /// reasons are skipped.
    static func removalReasons(
        from removedComments: [Lemmy.ModRemoveCommentView]
    ) -> [Int64: String] {
        var reasons: [Int64: String] = [:]
        for view in removedComments {
            let entry = view.mod_remove_comment
            guard entry.removed, let reason = entry.reason, !reason.isEmpty else { continue }
            let commentId = Int64(entry.comment_id)
            if reasons[commentId] == nil {
                reasons[commentId] = reason
            }
        }
        return reasons
    }

    private func mirrorCommentsToAppDatabase(
        serverPostId: Lemmy.PostID,
        sortType: Lemmy.CommentSortType,
        comments: [Lemmy.CommentView]
    ) async throws {
        guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(
                description: "mirrorCommentsToAppDatabase: account/site not found for \(accountIdentifierForLogging)"
            )
        }
        try await appDatabase.upsertComments(
            forServerPostId: Int64(serverPostId),
            accountId: accountRowId,
            siteId: siteRowId,
            sortType: sortType,
            comments: comments
        )
    }

    public func fetchSiteInfo() async throws {
        _ = try await getSiteInfo()
    }

    @discardableResult
    public func getSiteInfo() async throws -> LemmyKit.SiteInfo {
        logger.debug("Fetch site for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")

        let siteInfo: LemmyKit.SiteInfo
        let myUser: LemmyKit.MyUser?
        do {
            if accountIsSignedOut {
                // A signed-out account has no `my_user`, so a single `getSite` is all
                // that's needed. (On v4 the separate `getMyUser` endpoint throws for a
                // signed-out viewer, so the combined fetch must not be used here.)
                siteInfo = try await api.getSiteNeutral()
                myUser = nil
            } else {
                // One combined fetch for the signed-in refresh: on v3 a SINGLE `getSite`
                // round-trip decodes BOTH halves — previously this issued two, since
                // `getMyUserNeutral()` re-fetches `getSite()` to reach the embedded
                // `my_user`. On v4 the two native endpoints (`getSite` / `getMyUser`)
                // run concurrently. `.myUser` is nil on a v3 signed-out response, but a
                // signed-in account always carries it.
                let combined = try await api.getSiteAndMyUserNeutral()
                siteInfo = combined.site
                myUser = combined.myUser
            }
        } catch {
            logger.error("""
                Fetch site failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            // Emit a durable diagnostic so the recurring "Fetch site failed" noise
            // is observable in About → Logs without any change to error propagation.
            var metadata: [String: String] = ["error": String(describing: error)]
            if case let .unknownServerError(httpStatus, _) = error as? LemmyApiError {
                metadata["httpStatus"] = String(httpStatus)
            }
            await diagnostics.record(
                category: .site,
                level: .error,
                event: "site.fetchFailed",
                message: "getSite failed",
                instance: api.instanceHostname,
                metadata: metadata
            )
            throw LemmyServiceError(from: error)
        }

        logger.debug("Fetch site complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")

        do {
            let (_, siteId) = try await appDatabase.upsertSite(from: siteInfo)
            let accountId = try await appDatabase.upsertAccount(
                keychainId: accountIdentifierForLogging,
                isSignedOut: accountIsSignedOut,
                siteId: siteId,
                myUser: myUser
            )
            if let myUser {
                try await appDatabase.setFollowedCommunities(
                    accountId: accountId,
                    follows: myUser.follows
                )
            }
        } catch {
            logger.error("AppDatabase fetchSiteInfo upsert failed: \(String(describing: error), privacy: .public)")
        }

        return siteInfo
    }

    public func setShowNsfw(_ showNsfw: Bool) async throws {
        guard !accountIsSignedOut else {
            // Signed-out accounts have no server settings to push; the local
            // client preference still governs feed filtering via the request
            // param, so this is a deliberate no-op rather than an error.
            logger.debug("""
                Set show_nsfw skipped - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            return
        }

        if await instanceCapabilities().can(.serverUserSettings) {
            logger.debug("""
                Set show_nsfw=\(showNsfw, privacy: .public) \
                for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)

            do {
                try await api.saveUserSettingsNeutral(showNSFW: showNsfw)
            } catch {
                logger.error("""
                    Set show_nsfw failed. \(String(describing: error), privacy: .public)
                    """)
                throw LemmyServiceError(from: error)
            }
        } else {
            // Skip the server push - the local pref still governs feed
            // filtering via the request param; the push resumes once Spud
            // speaks this instance's API.
            await recordCapabilityBlocked(.serverUserSettings)
        }

        // Mirror the new value onto the local account row so the cached
        // `AccountRecord.showNsfw` stays in sync with the server.
        do {
            try await appDatabase.setAccountShowNsfw(
                showNsfw,
                forKeychainId: accountIdentifierForLogging
            )
        } catch {
            logger.error("""
                Mirror show_nsfw to AppDatabase failed. \(String(describing: error), privacy: .public)
                """)
        }
    }

    public func setBlurNsfw(_ blurNsfw: Bool) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Set blur_nsfw skipped - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            return
        }

        if await instanceCapabilities().can(.serverUserSettings) {
            logger.debug("""
                Set blur_nsfw=\(blurNsfw, privacy: .public) \
                for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)

            do {
                try await api.saveUserSettingsNeutral(blurNSFW: blurNsfw)
            } catch {
                logger.error("""
                    Set blur_nsfw failed. \(String(describing: error), privacy: .public)
                    """)
                throw LemmyServiceError(from: error)
            }
        } else {
            // Skip the server push - blur is a pure client-side render concern
            // and the local pref still applies; the push resumes once Spud
            // speaks this instance's API.
            await recordCapabilityBlocked(.serverUserSettings)
        }

        // Mirror the new value onto the local account row so the cached
        // `AccountRecord.blurNsfw` stays in sync with the server.
        do {
            try await appDatabase.setAccountBlurNsfw(
                blurNsfw,
                forKeychainId: accountIdentifierForLogging
            )
        } catch {
            logger.error("""
                Mirror blur_nsfw to AppDatabase failed. \(String(describing: error), privacy: .public)
                """)
        }
    }

    public func setDefaultSortType(_ sortType: Lemmy.SortType) async throws {
        guard !accountIsSignedOut else {
            // Signed-out accounts have no server settings to push; the local
            // account record still holds the default sort, so this is a
            // deliberate no-op rather than an error.
            logger.debug("""
                Set default_sort_type skipped - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            return
        }

        guard await instanceCapabilities().can(.serverUserSettings) else {
            // AccountServiceType already persisted the local default sort
            // synchronously (the local source of truth); skip the server
            // push until Spud speaks this instance's API.
            await recordCapabilityBlocked(.serverUserSettings)
            return
        }

        logger.debug("""
            Set default_sort_type=\(sortType.rawValue, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
            """)

        do {
            // Un-fuse the v3 `Top*` sort into the neutral sort + time-window pair so
            // the pushed default preserves its window (e.g. Top-Week stays Top-Week
            // rather than collapsing to Top-All).
            let (neutralSort, timeRange) = sortType.neutralPostSort
            try await api.saveUserSettingsNeutral(
                defaultSortType: neutralSort,
                defaultTimeRange: timeRange
            )
        } catch {
            logger.error("""
                Set default_sort_type failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func saveProfile(
        displayName: String?,
        bio: String?,
        avatar: ProfileImageEdit,
        banner: ProfileImageEdit,
        showScores: Bool,
        showBotAccounts: Bool,
        showReadPosts: Bool,
        showAvatars: Bool,
        defaultListingType: Lemmy.ListingType
    ) async throws {
        try await requireCapability(.serverUserSettings)

        guard !accountIsSignedOut else {
            // Editing a profile only makes sense for a real account: there is no
            // server-side profile for the anonymous placeholder, so this is an
            // error rather than a silent no-op (unlike the single-setting setters
            // whose values still apply locally).
            logger.debug("""
                Save profile rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Save profile for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
            """)

        let avatarMirror: String?
        let bannerMirror: String?
        do {
            // Push the avatar/banner images FIRST, ahead of the text settings and
            // the local mirror. v4 moved avatar/banner off saveUserSettings to
            // dedicated upload/delete endpoints; the neutral setters hide that
            // split (v3 uploads to pict-rs then writes the url). Ordering the image
            // push before the mirror keeps failure handling consistent with the
            // rest of the save: a push error throws out of saveProfile and nothing
            // stale is mirrored (there is nothing to roll back), exactly like a
            // failed settings push.
            avatarMirror = try await pushAvatarEdit(avatar)
            bannerMirror = try await pushBannerEdit(banner)

            try await api.saveUserSettingsNeutral(
                defaultListingType: defaultListingType,
                displayName: displayName,
                bio: bio,
                showScores: showScores,
                showBotAccounts: showBotAccounts,
                showReadPosts: showReadPosts,
                showAvatars: showAvatars
            )
        } catch {
            logger.error("""
                Save profile failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Mirror the new values onto the local person / account rows so the
        // cached profile reflects the edit immediately, without waiting on the
        // network. This is the optimistic path the open editor / Account header
        // observe. `avatarMirror` / `bannerMirror` are nil for an unchanged image
        // (leave the cached value), "" for a removal (clear it), or the pushed
        // url for a new image.
        do {
            try await appDatabase.setAccountProfile(
                forKeychainId: accountIdentifierForLogging,
                displayName: displayName,
                bio: bio,
                avatar: avatarMirror,
                banner: bannerMirror,
                showScores: showScores,
                showBotAccounts: showBotAccounts,
                showReadPosts: showReadPosts,
                showAvatars: showAvatars,
                defaultListingType: defaultListingType
            )
        } catch {
            logger.error("""
                Mirror profile to AppDatabase failed. \(String(describing: error), privacy: .public)
                """)
        }

        // Re-fetch getSite so the server's canonical view of `my_user`
        // (including any normalization the backend applied) re-imports over the
        // optimistic mirror. Best-effort: a failed refresh leaves the mirrored
        // values in place rather than failing the save the user already made.
        do {
            try await fetchSiteInfo()
        } catch {
            logger.error("""
                Refresh site after save profile failed. \(String(describing: error), privacy: .public)
                """)
        }
    }

    /// Pushes an avatar `ProfileImageEdit` to the server via the neutral
    /// avatar endpoints and returns the value to mirror onto the local person
    /// row: nil to leave the cached avatar unchanged, "" to clear it, or the new
    /// url. Throws on a server failure so the caller can surface it (the durable
    /// counterpart of the editor's optimistic preview).
    private func pushAvatarEdit(_ edit: ProfileImageEdit) async throws -> String? {
        switch edit {
        case .unchanged:
            return nil
        case .removed:
            try await api.removeAvatarNeutral()
            return ""
        case let .set(imageData, fileName, contentType):
            let url = try await api.setAvatarNeutral(
                imageData: imageData,
                fileName: fileName,
                contentType: contentType
            )
            // v3 always synthesizes a url; on v4 a nil means the response url
            // failed to parse — leave the mirror as-is and let the post-save
            // getSite re-import reconcile it to the server's canonical value.
            return url?.absoluteString
        }
    }

    /// The banner twin of `pushAvatarEdit`, targeting the neutral banner
    /// endpoints. Returns the value to mirror onto the local person row.
    private func pushBannerEdit(_ edit: ProfileImageEdit) async throws -> String? {
        switch edit {
        case .unchanged:
            return nil
        case .removed:
            try await api.removeBannerNeutral()
            return ""
        case let .set(imageData, fileName, contentType):
            let url = try await api.setBannerNeutral(
                imageData: imageData,
                fileName: fileName,
                contentType: contentType
            )
            return url?.absoluteString
        }
    }

    public func fetchPersonInfo(
        serverPersonId: Lemmy.PersonID
    ) async throws {
        try await requireCapability(.personProfiles)

        logger.debug("""
            Fetch person info. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public)
            """)

        let details: LemmyKit.PersonDetails
        do {
            details = try await api.personDetailsNeutral(personId: Int64(serverPersonId))
        } catch {
            logger.error("""
                Fetch person info failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch person info complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public)
            """)

        await mirrorPersonInfoToAppDatabase(personView: details.personView)

        guard appDatabase.personRowIdSync(
            forKeychainId: accountIdentifierForLogging,
            personId: Int64(serverPersonId)
        ) != nil else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchPersonInfo: person row not persisted after mirror for personId=\(serverPersonId)"
            )
        }
    }

    public func fetchPersonContent(
        serverPersonId: Lemmy.PersonID,
        sort: Lemmy.SortType,
        page: Int64
    ) async throws -> PersonContentPage {
        try await requireCapability(.personProfiles)

        logger.debug("""
            Fetch person content. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public) sort=\(sort.rawValue, privacy: .public) \
            page=\(page, privacy: .public)
            """)

        // v4 split a person's profile (`personDetailsNeutral`) from their paged
        // post/comment feed (`personContentNeutral`); Spud fetches both. NOTE: the
        // neutral content feed is cursor-paged and ignores `sort`; the v3 backend
        // encodes its page number as a bare-integer cursor, so page N > 1 maps to a
        // cursor of "N". See the Phase 6 report follow-ups (sort + v4 cursor paging).
        let details: LemmyKit.PersonDetails
        let contentPage: Page<LemmyKit.PostOrComment>
        do {
            let cursor = page <= 1 ? nil : Cursor(rawValue: String(page))
            details = try await api.personDetailsNeutral(personId: Int64(serverPersonId))
            contentPage = try await api.personContentNeutral(
                personId: Int64(serverPersonId),
                pageCursor: cursor
            )
        } catch {
            logger.error("""
                Fetch person content failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        let posts = contentPage.items.compactMap(\.post)
        let comments = contentPage.items.compactMap(\.comment)

        // Persist the posts as real PostRecords first (so the profile's Posts
        // tab renders them with the canonical PostListPostCell and gets live
        // vote/save updates). The post import also upserts each post's bare
        // creator person, so mirror the richer profile AFTER that — the full
        // profile (display name, bio, banner, counts) must win over the lean
        // creator embedded on a post. The comments stay transient (returned).
        await mirrorPersonPostsToAppDatabase(posts: posts)
        await mirrorPersonInfoToAppDatabase(personView: details.personView)

        return PersonContentPage(posts: posts, comments: comments)
    }

    /// Persists the person's posts so the profile's Posts tab can observe them
    /// as `PostListRow`s (feed parity). Best-effort: a failure leaves the posts
    /// unpersisted (the caller's transient comments are unaffected).
    private func mirrorPersonPostsToAppDatabase(
        posts: [Lemmy.PostView]
    ) async {
        guard !posts.isEmpty else { return }
        do {
            guard let (accountId, siteId) = try await accountSiteIds() else { return }
            try await appDatabase.upsertPosts(from: posts, accountId: accountId, siteId: siteId)
        } catch {
            logger.error("Failed to mirror person posts to AppDatabase: \(String(describing: error), privacy: .public)")
        }
    }

    private func mirrorPersonInfoToAppDatabase(
        personView: Lemmy.PersonView
    ) async {
        do {
            guard let (_, siteId) = try await accountSiteIds() else { return }
            try await appDatabase.upsertPerson(from: personView, siteId: siteId)
        } catch {
            logger.error("Failed to mirror person info to AppDatabase: \(String(describing: error), privacy: .public)")
        }
    }

    public func fetchCommunityInfo(
        serverCommunityId: Lemmy.CommunityID
    ) async throws {
        logger.debug("""
            Fetch community info. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        let view: Lemmy.CommunityView
        do {
            view = try await api.getCommunityNeutral(id: Int64(serverCommunityId))
        } catch {
            logger.error("""
                Fetch community info failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommunityInfoToAppDatabase(view: view)
    }

    @discardableResult
    public func fetchCommunityInfo(
        communityName: String
    ) async throws -> Lemmy.CommunityID {
        logger.debug("""
            Fetch community info. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityName=\(communityName, privacy: .public)
            """)

        // The neutral surface has no get-community-by-name endpoint, so resolve the
        // community by its federation actor url (`resolveObjectNeutral` works on
        // v3 and v4). `communityName` is either `local` (a community on the home
        // instance) or `local@host` (a federated one).
        let object: LemmyKit.ResolvedObject?
        do {
            let query = try await communityActorUrl(forName: communityName)
            object = try await api.resolveObjectNeutral(query: query)
        } catch {
            logger.error("""
                Fetch community info failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityName=\(communityName, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        guard let view = object?.community else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchCommunityInfo: '\(communityName)' did not resolve to a community"
            )
        }

        await mirrorCommunityInfoToAppDatabase(view: view)

        return Lemmy.CommunityID(view.community.id)
    }

    /// Builds a community's federation actor url from a `local` or `local@host`
    /// name, using the account's home instance host for a bare local name.
    private func communityActorUrl(forName name: String) async throws -> String {
        let parts = name.split(separator: "@", maxSplits: 1).map(String.init)
        let localName = parts.first ?? name
        let host: String
        if parts.count == 2 {
            host = parts[1]
        } else if let homeHost = await resolveInstanceHost() {
            host = homeHost
        } else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchCommunityInfo: no home instance to resolve local community '\(name)'"
            )
        }
        return "https://\(host)/c/\(localName)"
    }

    public func resolveObject(query: String) async throws -> ResolvedLemmyObject {
        let response = try await api.resolveObjectNeutral(query: query)
        // Resolve under the current account, so the returned ids are local to
        // this account's home instance. Use the async read (not the *Sync
        // variant) so we don't block the actor's executor.
        let rawActorId = await appDatabase.accountInstanceActorId(forKeychainId: accountIdentifierForLogging)
        let homeInstance = rawActorId.flatMap { InstanceActorId(from: $0) } ?? .invalid
        if !homeInstance.isValid {
            logger.warning("resolveObject: could not resolve a home instance for the current account; resolved ids will carry an invalid instance")
        }
        return ResolvedLemmyObject(response: response, homeInstance: homeInstance)
    }

    public func search(
        query: String,
        type: Lemmy.SearchType,
        sort: Lemmy.SortType,
        listingType: Lemmy.ListingType,
        page: Int64
    ) async throws -> LemmyKit.SearchResults {
        logger.debug("""
            Search. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            query=\(query, privacy: .private) type=\(type.rawValue, privacy: .public) \
            sort=\(sort.rawValue, privacy: .public) listingType=\(listingType.rawValue, privacy: .public) \
            page=\(page, privacy: .public)
            """)

        // NOTE: `searchNeutral` has no listing-type param (search is instance-wide),
        // so `listingType` is ignored here; `page` becomes an opaque cursor (page N
        // > 1 encodes as "N" for the v3 backend). See the Phase 6 report follow-ups.
        let (neutralSort, timeRange) = sort.neutralPostSort
        let cursor = page <= 1 ? nil : Cursor(rawValue: String(page))
        let results: LemmyKit.SearchResults
        do {
            results = try await api.searchNeutral(
                query: query,
                type: type.neutralSearchType,
                sort: neutralSort,
                timeRange: timeRange,
                pageCursor: cursor
            )
        } catch {
            logger.error("""
                Search failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                type=\(type.rawValue, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return results
    }

    public func listCommunities(
        type: Lemmy.ListingType,
        sort: Lemmy.SortType?,
        limit: Int64?
    ) async throws -> [Lemmy.CommunityView] {
        logger.debug("""
            List communities. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            type=\(type.rawValue, privacy: .public) \
            sort=\(sort?.rawValue ?? "default", privacy: .public) \
            limit=\(limit ?? -1, privacy: .public)
            """)

        // NOTE: `listCommunitiesNeutral` lists all communities with a single
        // `sort`; it takes no listing-`type`, NSFW, or `limit` param, so those are
        // ignored here (the caller trims the returned page). See Phase 6 follow-ups.
        let neutralSort = (sort ?? .Active).neutralPostSort.sort
        let page: Page<Lemmy.CommunityView>
        do {
            page = try await api.listCommunitiesNeutral(sort: neutralSort)
        } catch {
            logger.error("""
                List communities failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                type=\(type.rawValue, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        if let limit {
            return Array(page.items.prefix(Int(limit)))
        }
        return page.items
    }

    public func setSubscribed(
        serverCommunityId: Lemmy.CommunityID,
        subscribed: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Set subscribed rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set subscribed=\(subscribed, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .community,
            entityServerId: Int64(serverCommunityId),
            desiredState: .subscribe(subscribed)
        ))
    }

    // internal: shared with LemmyService+Safety
    func mirrorCommunityInfoToAppDatabase(
        view: Lemmy.CommunityView
    ) async {
        do {
            guard let (accountRowId, _) = try await accountSiteIds() else { return }
            try await appDatabase.upsertCommunity(from: view, accountId: accountRowId)
        } catch {
            logger.error("AppDatabase upsertCommunity failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func vote(
        serverPostId: Lemmy.PostID,
        vote action: VoteStatus.Action
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Vote rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        let currentVoteStatus: VoteStatus
        do {
            currentVoteStatus = try await appDatabase.postVoteStatus(
                forAccountKeychainId: accountIdentifierForLogging,
                serverPostId: serverPostId
            )
        } catch {
            logger.error("Failed to read post vote status: \(String(describing: error), privacy: .public)")
            throw LemmyServiceError.internalInconsistency(description: "post vote status lookup failed: \(error.localizedDescription)")
        }

        let desired = currentVoteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (desired '\(desired, privacy: .public)') \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .post,
            entityServerId: Int64(serverPostId),
            desiredState: .vote(desired)
        ))

        // Log the vote for the Activity timeline (best-effort: never throws to the caller).
        if let (accountRowId, _) = try? await accountSiteIds() {
            let snapshot = try? await appDatabase.postVoteSnapshot(
                forAccountKeychainId: accountIdentifierForLogging,
                serverPostId: serverPostId
            )
            await writeVoteEvent(
                accountId: accountRowId,
                entityType: "post",
                entityServerId: Int64(serverPostId),
                desired: desired,
                snapshot: snapshot
            )
        }
    }

    public func vote(
        serverCommentId: Lemmy.CommentID,
        vote action: VoteStatus.Action
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Vote rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(serverCommentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        let currentVoteStatus: VoteStatus
        do {
            currentVoteStatus = try await appDatabase.commentVoteStatus(
                forAccountKeychainId: accountIdentifierForLogging,
                serverCommentId: serverCommentId
            )
        } catch {
            logger.error("Failed to read comment vote status: \(String(describing: error), privacy: .public)")
            throw LemmyServiceError.internalInconsistency(description: "comment vote status lookup failed: \(error.localizedDescription)")
        }

        let desired = currentVoteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (desired '\(desired, privacy: .public)') \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .comment,
            entityServerId: Int64(serverCommentId),
            desiredState: .vote(desired)
        ))

        // Log the vote for the Activity timeline (best-effort: never throws to the caller).
        if let (accountRowId, _) = try? await accountSiteIds() {
            let snapshot = try? await appDatabase.commentVoteSnapshot(
                forAccountKeychainId: accountIdentifierForLogging,
                serverCommentId: serverCommentId
            )
            await writeVoteEvent(
                accountId: accountRowId,
                entityType: "comment",
                entityServerId: Int64(serverCommentId),
                desired: desired,
                snapshot: snapshot
            )
        }
    }

    // MARK: - Vote event log

    private func writeVoteEvent(
        accountId: Int64,
        entityType: String,
        entityServerId: Int64,
        desired: LikeStatus,
        snapshot: VoteEventSnapshot?
    ) async {
        switch desired {
        case .liked:
            try? await appDatabase.upsertVoteEvent(
                accountId: accountId,
                entityType: entityType,
                entityServerId: entityServerId,
                voteAction: 1,
                votedAt: Date().timeIntervalSince1970,
                title: snapshot?.title,
                body: snapshot?.body,
                communityName: snapshot?.communityName,
                communityActorId: snapshot?.communityActorId,
                thumbnailUrl: snapshot?.thumbnailUrl,
                score: snapshot?.score
            )
        case .disliked:
            try? await appDatabase.upsertVoteEvent(
                accountId: accountId,
                entityType: entityType,
                entityServerId: entityServerId,
                voteAction: 0,
                votedAt: Date().timeIntervalSince1970,
                title: snapshot?.title,
                body: snapshot?.body,
                communityName: snapshot?.communityName,
                communityActorId: snapshot?.communityActorId,
                thumbnailUrl: snapshot?.thumbnailUrl,
                score: snapshot?.score
            )
        case .neutral:
            try? await appDatabase.deleteVoteEvent(
                accountId: accountId,
                entityType: entityType,
                entityServerId: entityServerId
            )
        }
    }

    public func createComment(
        serverPostId: Lemmy.PostID,
        content: String,
        parentCommentId: Lemmy.CommentID?
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Create comment rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Create comment for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public) \
            parentCommentId=\(parentCommentId.map(String.init) ?? "nil", privacy: .public)
            """)

        let view: Lemmy.CommentView
        do {
            view = try await api.createCommentNeutral(
                content: content,
                postId: Int64(serverPostId),
                parentId: parentCommentId.map { Int64($0) },
                languageId: nil
            )
        } catch {
            logger.error("""
                Create comment failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommentToAppDatabase(view: view)
    }

    @discardableResult
    public func createPost(
        serverCommunityId: Lemmy.CommunityID,
        name: String,
        url: String?,
        body: String?,
        nsfw: Bool
    ) async throws -> Lemmy.PostID {
        guard !accountIsSignedOut else {
            logger.debug("""
                Create post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Create post for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        let view: Lemmy.PostView
        do {
            view = try await api.createPostNeutral(
                name: name,
                communityId: Int64(serverCommunityId),
                url: url,
                body: body,
                nsfw: nsfw,
                languageId: nil
            )
        } catch {
            logger.error("""
                Create post failed. communityId=\(serverCommunityId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorPostInfoToAppDatabase(view: view)
        return Lemmy.PostID(view.post.id)
    }

    public func uploadImage(
        imageData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> URL {
        try await requireCapability(.imageUpload)

        guard !accountIsSignedOut else {
            logger.debug("""
                Image upload rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Upload image for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            bytes=\(imageData.count, privacy: .public)
            """)

        // The neutral `uploadImageNeutral` takes no `mimeType` (it is inferred);
        // `mimeType` is retained on this method's signature but unused.
        let uploaded: LemmyKit.UploadedImage
        do {
            uploaded = try await api.uploadImageNeutral(
                imageData: imageData,
                fileName: fileName
            )
        } catch {
            logger.error("""
                Image upload failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        guard let url = uploaded.imageURL else {
            throw LemmyServiceError.internalInconsistency(
                description: "uploadImage: upload returned no image url"
            )
        }
        return url
    }

    public func setSaved(
        serverPostId: Lemmy.PostID,
        saved: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Save post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set saved=\(saved, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .post,
            entityServerId: Int64(serverPostId),
            desiredState: .save(saved)
        ))
    }

    public func setSaved(
        serverCommentId: Lemmy.CommentID,
        saved: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Save comment rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(serverCommentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set saved=\(saved, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .comment,
            entityServerId: Int64(serverCommentId),
            desiredState: .save(saved)
        ))
    }

    public func deleteComment(
        serverCommentId: Lemmy.CommentID,
        deleted: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Delete comment rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(serverCommentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set deleted=\(deleted, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .comment,
            entityServerId: Int64(serverCommentId),
            desiredState: .delete(deleted)
        ))
    }

    public func deletePost(
        serverPostId: Lemmy.PostID,
        deleted: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Delete post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set deleted=\(deleted, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .post,
            entityServerId: Int64(serverPostId),
            desiredState: .delete(deleted)
        ))
    }

    func mirrorCommentToAppDatabase(
        view: Lemmy.CommentView
    ) async {
        do {
            guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
                return
            }
            try await appDatabase.upsertComment(
                from: view,
                accountId: accountRowId,
                siteId: siteRowId
            )
        } catch {
            logger.error("AppDatabase upsertComment failed: \(String(describing: error), privacy: .public)")
        }
    }
}
