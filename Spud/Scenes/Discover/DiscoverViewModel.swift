//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
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

/// State of the optional "search the live network" step, offered while the user
/// is searching so communities missing from the bundled directory are findable.
enum NetworkSearchPhase: Equatable {
    case idle
    case searching
    case loaded
    case failed
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
    private let accountScope: AccountScope

    var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    @ObservationIgnored
    let isSignedIn: Bool

    /// Free-text filter from the nav-bar search controller.
    var searchText: String = "" {
        didSet {
            recomputeDirectory()
            // A new query invalidates any prior network search.
            networkSearchPhase = .idle
            networkResults = []
        }
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

    /// Live Lemmy community search results (deduped against the local directory),
    /// shown under the local matches when the user runs a network search.
    private(set) var networkResults: [CommunityListRow] = []
    /// Progress of the optional network search for the current query.
    private(set) var networkSearchPhase: NetworkSearchPhase = .idle

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
    /// Lazily-loaded snapshot of the Explorer instance directory, cached so the
    /// instance info card doesn't re-read all instances on every drill-in.
    @ObservationIgnored
    private var explorerSiteRows: [SiteListRow]?
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
    /// The account's NSFW preference (Lemmy `show_nsfw`). When off, NSFW
    /// communities are filtered out of the directory; when on, they show
    /// (badged). Curated rails stay clean regardless.
    @ObservationIgnored
    private let showNsfw: Bool

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(
        accountScope: AccountScope,
        isSignedIn: Bool,
        dependencies: Dependencies,
        onOpenCommunity: @escaping (CommunityListRow) -> Void,
        onOpenPack: @escaping (ResolvedStarterPack) -> Void,
        onOpenInstance: @escaping (InstanceSummary) -> Void,
        onRequestSignIn: @escaping () -> Void
    ) {
        self.accountScope = accountScope
        self.isSignedIn = isSignedIn
        self.dependencies = dependencies
        self.onOpenCommunity = onOpenCommunity
        self.onOpenPack = onOpenPack
        self.onOpenInstance = onOpenInstance
        self.onRequestSignIn = onRequestSignIn
        showNsfw = dependencies.appDatabase.accountShowNsfwSync(forKeychainId: accountScope.accountKeychainId)

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
        if isSignedIn, let accountRowId = appDatabase.accountRowIdSync(forKeychainId: accountScope.accountKeychainId) {
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

    /// Instance-level directory metadata (members, description, trust score) for
    /// `host`, when the Explorer instance directory has a record for it. Backs the
    /// instance info card atop the browse screen. Returns nil when the host isn't
    /// in the instance directory — the community and instance directories are
    /// separate datasets, so a host can appear in community rows without one.
    /// The full instance directory is read once, lazily, and cached.
    func instanceInfo(forHost host: String) -> SiteListRow? {
        if explorerSiteRows == nil {
            explorerSiteRows = dependencies.appDatabase.explorerSiteListRowsSync()
        }
        return explorerSiteRows?.first { $0.hostname.caseInsensitiveCompare(host) == .orderedSame }
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

    // MARK: Context-menu actions

    /// Whether `row` is currently muted for this account (client-local).
    func isMuted(_ row: CommunityListRow) -> Bool {
        dependencies.appDatabase.isCommunityMutedSync(
            forKeychainId: accountKeychainId,
            communityActorId: row.communityUrl
        )
    }

    /// Mute `row` for `duration`. Muting is client-local (no server round-trip),
    /// keyed by the community's actor id, so it works for any account.
    func mute(_ row: CommunityListRow, duration: MuteDuration) {
        Haptics.tap()
        dependencies.appDatabase.muteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: row.communityUrl,
            until: duration.until
        )
    }

    func unmute(_ row: CommunityListRow) {
        Haptics.tap()
        dependencies.appDatabase.unmuteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: row.communityUrl
        )
    }

    /// Block `row` on the user's instance. Like Follow, the Explorer row is first
    /// resolved to a server community id. Signed-out accounts hit the sign-in gate.
    func block(_ row: CommunityListRow) {
        guard isSignedIn else {
            onRequestSignIn()
            return
        }
        Haptics.tap()
        Task { [weak self] in
            guard let self else { return }
            do {
                let lemmyService = accountScope.lemmyService
                let serverCommunityId = try await lemmyService
                    .fetchCommunityInfo(communityName: "\(row.name)@\(row.instanceHost)")
                try await lemmyService.setBlocked(serverCommunityId: serverCommunityId, blocked: true)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .setBlockedCommunity)
            }
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
                let lemmyService = accountScope.lemmyService
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

    /// Search the live Lemmy network for communities matching the current query,
    /// mapping results into directory rows and dropping any already shown from the
    /// bundled directory (and NSFW unless the account allows it).
    func searchNetwork() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, networkSearchPhase != .searching else { return }
        networkSearchPhase = .searching

        Task { [weak self] in
            guard let self else { return }
            do {
                let lemmyService = accountScope.lemmyService
                let response = try await lemmyService.search(
                    query: query,
                    type: .Communities,
                    sort: .TopAll,
                    listingType: .All,
                    page: 1
                )
                if Task.isCancelled { return }
                // Drop stale results if the query changed while we were waiting.
                guard searchText.trimmingCharacters(in: .whitespaces) == query else { return }

                let localUrls = Set(directory.map(\.communityUrl))
                networkResults = response.communities
                    .compactMap(CommunityListRow.init(searchView:))
                    .filter { !localUrls.contains($0.communityUrl) && (showNsfw || !$0.isNsfw) }
                networkSearchPhase = .loaded
            } catch {
                networkSearchPhase = .failed
                alertService.handle(error, for: .search)
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
        // Suspicious communities are always excluded from the directory; NSFW is
        // governed by the account's `show_nsfw` setting. Same-name communities
        // collapse to one canonical entry.
        let filter = ExplorerCommunityFilter(hideNsfw: !showNsfw, hideSuspicious: true)
        directory = ExplorerCommunityDirectory.apply(
            to: allRows,
            query: searchText,
            filter: filter,
            sort: sort,
            dedupeSameName: true
        )
    }
}
