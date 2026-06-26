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

    // MARK: Content state (transient)

    var tab: PersonContentTab = .posts
    var phase: PersonContentPhase = .loading
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
    let serverPersonId: Components.Schemas.PersonID
    @ObservationIgnored
    let accountScope: AccountScope
    @ObservationIgnored
    private let accountService: AccountServiceType
    /// The sort applied to the profile's posts and comments (one fetch covers
    /// both). Mutable so the navbar sort menu can change it; per-screen only,
    /// it does not change the account's default sort.
    @ObservationIgnored
    private(set) var sortType: Components.Schemas.SortType

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var contentTask: Task<Void, Never>?

    init(
        personRowId: Int64?,
        serverPersonId: Components.Schemas.PersonID,
        accountScope: AccountScope,
        accountService: AccountServiceType,
        appDatabase: AppDatabase
    ) {
        self.serverPersonId = serverPersonId
        self.accountScope = accountScope
        self.accountService = accountService
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
    }

    deinit {
        observationTask?.cancel()
        contentTask?.cancel()
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
        numberOfPosts = CommentsFormatter.string(from: row.numberOfPosts)
        numberOfComments = CommentsFormatter.string(from: row.numberOfComments)
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
    /// independently; this only drives the posts/comments lists.
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

    /// Changes the sort order for the profile's posts and comments and reloads.
    /// A single fetch returns both tabs, so one sort applies to the whole
    /// profile. Per-screen only; does not change the account default.
    func changeSortType(_ newSort: Components.Schemas.SortType) {
        guard newSort != sortType else { return }
        sortType = newSort
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
