//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import OSLog
import SpudDataKit
import SpudUIKit

private let logger = Logger.app

/// Follow state for the inline Follow control on Discover, derived from the
/// account's real subscriptions: `.following` for communities the account
/// already follows (so the button is correct from the first render),
/// `.inFlight` while a follow/unfollow request is running, else `.idle`.
enum CommunityFollowState: Equatable {
    case idle
    case inFlight
    case following
}

/// View model for the Discover (Community Explorer) screen. Observes the whole
/// Explorer community directory and derives the rails — Trending and Rising —
/// plus the sortable/searchable "All communities" directory, all via the pure
/// ``ExplorerCommunityDirectory``. Opening a community is delegated to the
/// hosting controller through `onOpenCommunity`; following resolves the
/// community by name and subscribes in place.
@MainActor
@Observable
final class DiscoverViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    let accountKeychainId: String

    @ObservationIgnored
    let isSignedIn: Bool

    /// Free-text filter from the nav-bar search controller.
    var searchText: String = "" {
        didSet { recomputeDirectory() }
    }

    /// Sort applied to the "All communities" directory.
    var sort: ExplorerCommunitySort = .recommended {
        didSet { recomputeDirectory() }
    }

    /// Curated bundles a new user can follow together, with live stats.
    private(set) var starterPacks: [ResolvedStarterPack] = []
    /// Busiest communities this week.
    private(set) var trending: [CommunityListRow] = []
    /// Small communities punching above their size.
    private(set) var rising: [CommunityListRow] = []
    /// Liveliest home instances, for the "Browse by instance" rail.
    private(set) var instances: [InstanceSummary] = []
    /// Active communities on the servers the account already follows, for the
    /// signed-in "Because you follow" rail.
    private(set) var becauseYouFollow: [CommunityListRow] = []
    /// The filtered, sorted, de-duplicated directory.
    private(set) var directory: [CommunityListRow] = []
    /// True until the first directory snapshot arrives.
    private(set) var isLoading = true

    /// When set, the same-name compare sheet is presented.
    var compareTarget: CompareTarget?

    /// Row ids with a follow/unfollow request in flight (shows the spinner).
    private(set) var inFlightRowIds: Set<Int64> = []
    /// Actor ids the account currently follows — the source of truth for the
    /// "Following" state, kept live by the subscriptions observation and updated
    /// optimistically on follow/unfollow. Also excluded from recommendations.
    private(set) var followedUrls: Set<String> = []

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ObservationIgnored
    private var allRows: [CommunityListRow] = []
    @ObservationIgnored
    private let onOpenCommunity: (CommunityListRow) -> Void
    @ObservationIgnored
    private let onOpenPack: (ResolvedStarterPack) -> Void
    @ObservationIgnored
    private let onOpenInstance: (InstanceSummary) -> Void
    @ObservationIgnored
    private let onRequestSignIn: () -> Void
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var followObservationTask: Task<Void, Never>?
    /// Home instances the account already follows communities on.
    @ObservationIgnored
    private var followedHosts: Set<String> = []

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies,
        onOpenCommunity: @escaping (CommunityListRow) -> Void,
        onOpenPack: @escaping (ResolvedStarterPack) -> Void,
        onOpenInstance: @escaping (InstanceSummary) -> Void,
        onRequestSignIn: @escaping () -> Void
    ) {
        self.accountKeychainId = accountKeychainId
        self.isSignedIn = isSignedIn
        self.dependencies = dependencies
        self.onOpenCommunity = onOpenCommunity
        self.onOpenPack = onOpenPack
        self.onOpenInstance = onOpenInstance
        self.onRequestSignIn = onRequestSignIn

        let appDatabase = dependencies.appDatabase
        observationTask = Task { [weak self] in
            for await rows in appDatabase.observeExplorerCommunityListRows() {
                if Task.isCancelled { break }
                guard let self else { return }
                allRows = rows
                recomputeRails()
                recomputeDirectory()
                isLoading = false
            }
        }

        // "Because you follow" needs the account's subscriptions; only observe
        // them for a signed-in account that resolves to a stored row.
        if isSignedIn, let accountRowId = appDatabase.accountRowIdSync(forKeychainId: accountKeychainId) {
            followObservationTask = Task { [weak self] in
                for await communities in appDatabase.observeFollowedCommunities(forAccountId: accountRowId) {
                    if Task.isCancelled { break }
                    guard let self else { return }
                    let urls = communities.compactMap(\.actorId)
                    followedUrls = Set(urls)
                    followedHosts = Set(urls.compactMap { URL(string: $0)?.host })
                    recomputeBecauseYouFollow()
                }
            }
        }
    }

    deinit {
        observationTask?.cancel()
        followObservationTask?.cancel()
    }

    func open(_ row: CommunityListRow) {
        onOpenCommunity(row)
    }

    func openPack(_ pack: ResolvedStarterPack) {
        onOpenPack(pack)
    }

    func openInstance(_ summary: InstanceSummary) {
        onOpenInstance(summary)
    }

    /// The curated-safe communities hosted on `host`, sorted by the current
    /// directory sort. Used to populate the instance browse screen.
    func communities(onInstance host: String) -> [CommunityListRow] {
        ExplorerCommunityDirectory.communities(onInstance: host, in: allRows, sort: sort)
    }

    /// Present the same-name compare sheet for `row`, listing every server that
    /// hosts a community with this name, busiest first.
    func compare(_ row: CommunityListRow) {
        compareTarget = CompareTarget(
            name: row.name,
            displayName: row.displayName,
            variants: ExplorerCommunityDirectory.variants(of: row.name, in: allRows)
        )
    }

    /// Dismiss the compare sheet and open the chosen variant's community page.
    func openFromCompare(_ row: CommunityListRow) {
        compareTarget = nil
        onOpenCommunity(row)
    }

    /// Follow state derived from the account's real subscriptions: an in-flight
    /// request wins, then membership in ``followedUrls``, else idle. So a
    /// community the account already follows correctly reads `.following`.
    func followState(for row: CommunityListRow) -> CommunityFollowState {
        if inFlightRowIds.contains(row.id) { return .inFlight }
        if followedUrls.contains(row.communityUrl) { return .following }
        return .idle
    }

    /// Toggle following for `row`: subscribe when idle, unsubscribe when already
    /// following. Signed-out accounts hit the sign-in gate; in-flight rows are
    /// ignored.
    func toggleFollow(_ row: CommunityListRow) {
        guard isSignedIn else {
            onRequestSignIn()
            return
        }
        switch followState(for: row) {
        case .inFlight:
            return
        case .idle:
            setSubscribed(row, subscribe: true)
        case .following:
            setSubscribed(row, subscribe: false)
        }
    }

    /// Follow every community in `communities` that isn't followed yet (used by
    /// the starter-pack "Follow all"). One sign-in gate for the whole batch.
    func followAll(_ communities: [CommunityListRow]) {
        guard isSignedIn else {
            onRequestSignIn()
            return
        }
        let pending = communities.filter { followState(for: $0) == .idle }
        guard !pending.isEmpty else { return }
        Haptics.tap()
        for row in pending {
            setSubscribed(row, subscribe: true, haptic: false)
        }
    }

    /// Resolve `row` by `name@instance` and (un)subscribe, updating the in-flight
    /// and followed sets so the buttons reflect the change without waiting on the
    /// subscriptions observation to round-trip.
    private func setSubscribed(_ row: CommunityListRow, subscribe: Bool, haptic: Bool = true) {
        guard !inFlightRowIds.contains(row.id) else { return }
        inFlightRowIds.insert(row.id)
        if haptic { Haptics.tap() }

        Task { [weak self] in
            guard let self else { return }
            defer { inFlightRowIds.remove(row.id) }
            do {
                let lemmyService = accountService.lemmyService(forAccountKeychainId: accountKeychainId)
                let serverCommunityId = try await lemmyService
                    .fetchCommunityInfo(communityName: "\(row.name)@\(row.instanceHost)")
                if Task.isCancelled { return }
                try await lemmyService.setSubscribed(serverCommunityId: serverCommunityId, subscribed: subscribe)
                if subscribe {
                    followedUrls.insert(row.communityUrl)
                } else {
                    followedUrls.remove(row.communityUrl)
                }
                recomputeBecauseYouFollow()
            } catch {
                alertService.handle(error, for: .setSubscribed)
            }
        }
    }

    private func recomputeRails() {
        starterPacks = StarterPackCatalog.resolve(using: allRows)
        trending = ExplorerCommunityDirectory.trending(in: allRows, limit: 12)
        rising = ExplorerCommunityDirectory.rising(in: allRows, limit: 12)
        instances = ExplorerCommunityDirectory.topInstances(in: allRows, limit: 12)
        recomputeBecauseYouFollow()
    }

    private func recomputeBecauseYouFollow() {
        becauseYouFollow = ExplorerCommunityDirectory.becauseYouFollow(
            in: allRows,
            followedHosts: followedHosts,
            excludingUrls: followedUrls,
            limit: 12
        )
    }

    private func recomputeDirectory() {
        // Curated surfaces stay clean: NSFW and suspicious are filtered out, and
        // same-name communities collapse to one canonical entry.
        let filter = ExplorerCommunityFilter(hideNsfw: true, hideSuspicious: true)
        directory = ExplorerCommunityDirectory.apply(
            to: allRows,
            query: searchText,
            filter: filter,
            sort: sort,
            dedupeSameName: true
        )
    }
}
