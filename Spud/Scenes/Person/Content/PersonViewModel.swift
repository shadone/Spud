//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit
import SpudUtilKit

private let logger = Logger.app

/// View model for the Person profile screen. The header fields are driven by
/// `appDatabase.observePersonProfile` (persisted), while the posts/comments
/// lists are transient - fetched per tab via `LemmyService.fetchPersonContent`
/// and held in memory, mirroring how Search returns its results.
@MainActor
@Observable
final class PersonViewModel {
    // MARK: Header state (observed from the database)

    var name: String = ""
    var homeInstance: String = ""
    var displayName: String?
    var avatarUrl: URL?
    var bannerUrl: URL?
    var bioMarkdown: String?
    /// The person's canonical profile URL (their federated actor id), used for
    /// the Share / Copy Link / Open in Browser actions. Nil until resolved.
    var profileURL: URL?

    // MARK: Account status (observed from the database)

    var isBanned: Bool = false
    var banExpires: Date?
    var isDeleted: Bool = false
    var isBotAccount: Bool = false
    var isAdmin: Bool = false
    var matrixUserId: String?

    /// User-facing instance-ban status (with expiry for a temporary ban), or
    /// nil when the user is not banned.
    var banStatusText: String? {
        PersonFormatter.banStatus(isBanned: isBanned, banExpires: banExpires)
    }

    var numberOfPosts: String = ""
    var numberOfComments: String = ""
    var cakeDay: String = ""
    /// Title used for the header / nav bar: display name when set, else name.
    var title: String = ""
    /// Canonical "@name@instance" handle.
    var handle: String = ""

    // MARK: Content state

    var tab: PersonContentTab = .posts
    var phase: PersonContentPhase = .loading

    /// The person's posts, persisted as real `PostRecord`s and read back as
    /// `PostListRow`s so the Posts tab renders with the canonical
    /// `PostListPostCell` (vote state, saved badge, density, NSFW blur, status
    /// badges) and updates live as votes / saves flow through the GRDB
    /// observation — exactly like the main feed. Empty until the post
    /// observation produces its first snapshot.
    private(set) var postRows: [PostListRow] = []

    /// The person's comments — still transient (`SearchCommentResult`), rendered
    /// by the comment-with-context cell, mirroring how Search returns results.
    private(set) var content = PersonContent()

    // MARK: Block state (transient, sourced from getSite -> my_user)

    /// Whether this person is currently blocked by the backing account.
    /// Resolved on appear via `fetchBlockedList`; updated optimistically by
    /// `setBlocked` and confirmed by the api response.
    var isBlocked: Bool = false
    /// True once the block state has been resolved from the server, so the UI
    /// can avoid showing a stale Block/Unblock label before it is known.
    var blockStateKnown: Bool = false

    // MARK: Private

    @ObservationIgnored
    let serverPersonId: Lemmy.PersonID
    @ObservationIgnored
    let accountScope: AccountScope
    @ObservationIgnored
    private let accountService: AccountServiceType
    /// The sort applied to the profile's posts and comments (one fetch covers
    /// both). Mutable so the navbar sort menu can change it; per-screen only,
    /// it does not change the account's default sort.
    @ObservationIgnored
    private(set) var sortType: Lemmy.SortType

    @ObservationIgnored
    private let appDatabase: AppDatabase
    @ObservationIgnored
    private let personRowId: Int64?

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var contentTask: Task<Void, Never>?
    /// The live GRDB observation feeding `postRows`. Restarted whenever the sort
    /// changes (a different `ORDER BY`) or a reload completes.
    @ObservationIgnored
    private var postObservationTask: Task<Void, Never>?

    init(
        personRowId: Int64?,
        serverPersonId: Lemmy.PersonID,
        accountScope: AccountScope,
        accountService: AccountServiceType,
        appDatabase: AppDatabase,
        initialTab: PersonContentTab = .posts
    ) {
        self.serverPersonId = serverPersonId
        self.accountScope = accountScope
        self.accountService = accountService
        self.appDatabase = appDatabase
        self.personRowId = personRowId
        tab = initialTab
        sortType = accountService.defaultSortType(forAccountKeychainId: accountScope.accountKeychainId)

        if let personRowId {
            observationTask = Task { [weak self] in
                for await row in appDatabase.observePersonProfile(personRowId: personRowId) {
                    if Task.isCancelled { break }
                    guard let row else { continue }
                    await MainActor.run { self?.apply(row: row) }
                }
            }
        }

        startPostObservation()
    }

    deinit {
        observationTask?.cancel()
        contentTask?.cancel()
        postObservationTask?.cancel()
    }

    /// Starts (or restarts) the live observation of the person's persisted posts
    /// as `PostListRow`s, ordered by the current sort. Resolved against the
    /// person's row id and the backing account's row id. A no-op when either id
    /// is unresolved (e.g. a profile reached before its row exists) — `postRows`
    /// stays empty until the next fetch persists posts and a restart picks them
    /// up.
    private func startPostObservation() {
        postObservationTask?.cancel()
        guard
            let personRowId,
            let accountId = appDatabase.accountRowIdSync(forKeychainId: accountScope.accountKeychainId)
        else { return }

        let appDatabase = appDatabase
        let sortType = sortType
        postObservationTask = Task { [weak self] in
            for await rows in appDatabase.observePersonPostListRows(
                personRowId: personRowId,
                accountId: accountId,
                sort: sortType
            ) {
                if Task.isCancelled { break }
                await MainActor.run { self?.postRows = rows }
            }
        }
    }

    private func apply(row: PersonProfileRow) {
        name = row.name
        homeInstance = "@\(row.instanceHostname)"
        displayName = row.displayName
        title = row.displayName ?? row.name
        handle = "@\(row.name)@\(row.instanceHostname)"
        avatarUrl = row.avatarUrl.flatMap { URL(string: $0) }
        bannerUrl = row.bannerUrl.flatMap { URL(string: $0) }
        bioMarkdown = row.bio
        profileURL = row.actorId.flatMap { URL(string: $0) }
        isBanned = row.isBanned
        banExpires = row.banExpires
        isDeleted = row.isDeleted
        isBotAccount = row.isBotAccount
        isAdmin = row.isAdmin
        matrixUserId = row.matrixUserId
        numberOfPosts = CountFormatter.string(row.numberOfPosts)
        numberOfComments = CountFormatter.string(row.numberOfComments)
        if let createdDate = row.personCreatedDate {
            cakeDay = PersonFormatter.cakeDayString(personCreatedDate: createdDate)
        } else {
            cakeDay = ""
        }
    }

    /// One-line stats summary shown under the handle: post karma, comment
    /// karma, and the cake day.
    var statsText: String {
        var pieces: [String] = []
        let posts = String(
            format: NSLocalizedString("%@ posts", comment: "Person header post count"),
            numberOfPosts
        )
        let comments = String(
            format: NSLocalizedString("%@ comments", comment: "Person header comment count"),
            numberOfComments
        )
        pieces.append(posts)
        pieces.append(comments)
        if !cakeDay.isEmpty {
            pieces.append("🎂 \(cakeDay)")
        }
        return pieces.joined(separator: "  ·  ")
    }

    // MARK: Content loading

    /// Loads (or reloads) the active tab's content. The header observation runs
    /// independently. The fetch persists the person's posts as real
    /// `PostRecord`s (picked up by the live `postRows` observation) and returns
    /// the comments transiently.
    func loadContent() {
        contentTask?.cancel()
        phase = .loading
        let serverPersonId = serverPersonId
        let sortType = sortType
        contentTask = Task { [weak self] in
            guard let self else { return }
            let lemmyService = accountScope.lemmyService
            do {
                let response = try await lemmyService.fetchPersonContent(
                    serverPersonId: serverPersonId,
                    sort: sortType,
                    page: 1
                )
                if Task.isCancelled { return }
                content = PersonContent(response: response)
                // The posts are now persisted; (re)start the live observation so
                // a profile reached before its person row existed, or before any
                // post was cached, still picks them up.
                startPostObservation()
                phase = .loaded
            } catch {
                if Task.isCancelled { return }
                logger.error("Fetch person content failed: \(String(describing: error), privacy: .public)")
                content = PersonContent()
                phase = .error
            }
        }
    }

    func tabChanged(_ newTab: PersonContentTab) {
        guard newTab != tab else { return }
        tab = newTab
    }

    /// Whether the active tab currently has nothing to show. Posts read from the
    /// live `postRows` observation; comments from the transient content.
    func isEmpty(for tab: PersonContentTab) -> Bool {
        switch tab {
        case .posts: postRows.isEmpty
        case .comments: content.comments.isEmpty
        }
    }

    /// Changes the sort order for the profile's posts and comments and reloads.
    /// A single fetch returns both tabs, so one sort applies to the whole
    /// profile. Per-screen only; does not change the account default. Restarts
    /// the post observation immediately so the already-cached posts reorder
    /// without waiting on the network, then re-fetches for the new sort.
    func changeSortType(_ newSort: Lemmy.SortType) {
        guard newSort != sortType else { return }
        sortType = newSort
        startPostObservation()
        loadContent()
    }

    // MARK: Block

    /// Resolves whether this person is currently blocked, from the server's
    /// `getSite` block list. Silently no-ops for signed-out accounts (which
    /// can't block) and on failure leaves `isBlocked` at its last value.
    func refreshBlockState() {
        guard !accountScope.isSignedOut else { return }
        let serverPersonId = serverPersonId
        Task { [weak self] in
            guard let self else { return }
            let lemmyService = accountScope.lemmyService
            do {
                let blocked = try await lemmyService.fetchBlockedList()
                if Task.isCancelled { return }
                isBlocked = blocked.persons.contains { $0.serverPersonId == serverPersonId }
                blockStateKnown = true
            } catch {
                logger.error("Refresh person block state failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Blocks or unblocks this person. Mirrors `isBlocked` optimistically and
    /// throws on failure so the caller can surface a designed error and revert.
    func setBlocked(_ blocked: Bool) async throws {
        let previous = isBlocked
        isBlocked = blocked
        do {
            try await accountScope
                .lemmyService
                .setBlocked(serverPersonId: serverPersonId, blocked: blocked)
            blockStateKnown = true
        } catch {
            isBlocked = previous
            throw error
        }
    }
}
