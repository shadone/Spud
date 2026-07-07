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

/// Subscription state for the inline Subscribe control on Discover, derived from
/// the account's real subscriptions: `.subscribed` for communities the account is
/// already subscribed to (so the button is correct from the first render),
/// `.inFlight` while a subscribe/unsubscribe request is running, else `.idle`.
enum CommunitySubscriptionState: Equatable {
    case idle
    case inFlight
    case subscribed
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
/// hosting controller through `onOpenCommunity`; subscribing resolves the
/// community by name and subscribes in place.
@MainActor
@Observable
final class DiscoverViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasNodeInfoService &
        HasPreferencesService
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

    /// Curated bundles a new user can subscribe to together, with live stats.
    private(set) var starterPacks: [ResolvedStarterPack] = []
    /// Busiest communities this week (ranked ``railDepth`` deep; the carousel shows
    /// the first ``railCarouselCount``, "See all" shows the rest).
    private(set) var trending: [CommunityListRow] = []
    /// Small communities punching above their size (see ``trending`` for depth).
    private(set) var rising: [CommunityListRow] = []
    /// Liveliest home instances, for the "Browse by instance" rail (see ``trending``).
    private(set) var instances: [InstanceSummary] = []
    /// Active communities on the servers the account already follows, for the
    /// signed-in "Because you follow" rail (see ``trending`` for depth).
    private(set) var becauseYouFollow: [CommunityListRow] = []
    /// The filtered, sorted, de-duplicated directory.
    private(set) var directory: [CommunityListRow] = []
    /// True until the first directory snapshot arrives.
    private(set) var isLoading = true

    /// Live NodeInfo metadata for the browse-instance header chips, keyed by host.
    /// Populated ONLY by ``loadInstanceMetadata(forHost:)`` when the user opens an
    /// instance browse screen — never by rail/directory rendering (the privacy
    /// boundary: probe only on explicit engagement, never while listing rails or
    /// feeds). Observed, so a chip appears in place when the async probe resolves.
    private(set) var instanceMetadata: [String: InstanceMetadata] = [:]

    /// How many rail items the horizontal carousel shows on the landing; the rest
    /// are reachable via the rail's "See all".
    static let railCarouselCount = 12
    /// How deep each rail is ranked, so "See all" surfaces a meaningful list beyond
    /// the carousel without materialising the whole directory.
    private static let railDepth = 60

    /// When set, the same-name compare sheet is presented.
    var compareTarget: CompareTarget?

    /// Live Lemmy community search results (deduped against the local directory),
    /// shown under the local matches when the user runs a network search.
    private(set) var networkResults: [CommunityListRow] = []
    /// Progress of the optional network search for the current query.
    private(set) var networkSearchPhase: NetworkSearchPhase = .idle

    /// Row ids with a subscribe/unsubscribe request in flight (shows the spinner).
    private(set) var inFlightRowIds: Set<Int64> = []
    /// Actor ids the account is currently subscribed to — the source of truth for
    /// the "Subscribed" state, kept live by the subscriptions observation and
    /// updated optimistically on subscribe/unsubscribe. Also excluded from
    /// recommendations.
    private(set) var subscribedUrls: Set<String> = []

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
    /// Push the full ranked list for a community rail ("See all"), titled by the rail.
    @ObservationIgnored
    private let onSeeAllCommunities: (String, [CommunityListRow]) -> Void
    /// Push the full ranked instance list for the Browse-by-instance rail.
    @ObservationIgnored
    private let onSeeAllInstances: (String, [InstanceSummary]) -> Void
    @ObservationIgnored
    private let onRequestSignIn: () -> Void
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var subscriptionsObservationTask: Task<Void, Never>?
    @ObservationIgnored
    private var nsfwObservationTask: Task<Void, Never>?
    @ObservationIgnored
    private var blurNsfwObservationTask: Task<Void, Never>?
    /// Home instances the account is already subscribed to communities on.
    @ObservationIgnored
    private var subscribedHosts: Set<String> = []
    /// The client's NSFW preference (`PreferencesService.showNsfw`, the
    /// authoritative client setting shared with the feeds). When off, NSFW
    /// communities are filtered out of the directory; when on, they show
    /// (badged). Curated rails stay clean regardless. Observed live so toggling
    /// it (in Settings or the post-list Quick Switch) re-filters an open Discover.
    @ObservationIgnored
    private var showNsfw: Bool
    /// Whether NSFW community icons should be obscured. Observed live so the
    /// view re-renders immediately when the user toggles Blur NSFW in Settings.
    private(set) var blurNsfw: Bool

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
        onSeeAllCommunities: @escaping (String, [CommunityListRow]) -> Void,
        onSeeAllInstances: @escaping (String, [InstanceSummary]) -> Void,
        onRequestSignIn: @escaping () -> Void
    ) {
        self.accountScope = accountScope
        self.isSignedIn = isSignedIn
        self.dependencies = dependencies
        self.onOpenCommunity = onOpenCommunity
        self.onOpenPack = onOpenPack
        self.onOpenInstance = onOpenInstance
        self.onSeeAllCommunities = onSeeAllCommunities
        self.onSeeAllInstances = onSeeAllInstances
        self.onRequestSignIn = onRequestSignIn
        showNsfw = dependencies.preferencesService.showNsfw
        blurNsfw = dependencies.preferencesService.blurNsfw

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

        // Re-filter live when the NSFW preference changes. The stream replays the
        // current value first; the equality guard skips that redundant recompute
        // (init already seeded `showNsfw`), so only real changes recompute.
        let preferencesService = dependencies.preferencesService
        nsfwObservationTask = Task { [weak self] in
            for await value in preferencesService.showNsfwStream {
                if Task.isCancelled { break }
                guard let self, value != showNsfw else { continue }
                showNsfw = value
                recomputeRails()
                recomputeDirectory()
            }
        }

        // Re-render live when the blur preference changes. The stream replays
        // the current value first; the equality guard skips the redundant first
        // emission (init already seeded `blurNsfw`).
        blurNsfwObservationTask = Task { [weak self] in
            for await value in preferencesService.blurNsfwStream {
                if Task.isCancelled { break }
                guard let self, value != blurNsfw else { continue }
                blurNsfw = value
            }
        }

        // "Because you follow" needs the account's subscriptions; only observe
        // them for a signed-in account that resolves to a stored row.
        if isSignedIn, let accountRowId = appDatabase.accountRowIdSync(forKeychainId: accountScope.accountKeychainId) {
            subscriptionsObservationTask = Task { [weak self] in
                for await communities in appDatabase.observeFollowedCommunities(forAccountId: accountRowId) {
                    if Task.isCancelled { break }
                    guard let self else { return }
                    let urls = communities.compactMap(\.actorId)
                    subscribedUrls = Set(urls)
                    subscribedHosts = Set(urls.compactMap { URL(string: $0)?.host })
                    recomputeBecauseYouFollow()
                }
            }
        }
    }

    deinit {
        observationTask?.cancel()
        subscriptionsObservationTask?.cancel()
        nsfwObservationTask?.cancel()
        blurNsfwObservationTask?.cancel()
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

    /// Open the full ranked list for a community rail (Trending / Rising / Because
    /// you follow). The rails are ranked ``railDepth`` deep but the landing only
    /// shows the first ``railCarouselCount`` in a carousel; "See all" pushes the rest.
    func seeAllCommunities(title: String, rows: [CommunityListRow]) {
        onSeeAllCommunities(title, rows)
    }

    /// Open the full ranked instance list for the Browse-by-instance rail.
    func seeAllInstances() {
        onSeeAllInstances(
            NSLocalizedString("Browse by instance", comment: "Discover instance rail See-all title"),
            instances
        )
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

    /// Live NodeInfo metadata for `host`, or nil when it has not been probed or the
    /// probe failed. Backs the browse-instance header's software + signups chips;
    /// a nil result means "unknown", so the chips are simply absent (fail-open, no
    /// placeholder).
    func metadata(forHost host: String) -> InstanceMetadata? {
        instanceMetadata[host]
    }

    /// Probe live NodeInfo metadata for `host` and publish it for the browse-
    /// instance header chips. Called once when the user opens an instance browse
    /// screen (``DiscoverViewController/openInstance(_:)``) — the explicit
    /// engagement that gates the probe. Never fired from rail/directory rendering,
    /// preserving the privacy boundary (no probing while listing rails or feeds).
    /// Fail-open: a nil probe result stores nothing, so the chips stay absent.
    /// Idempotent per host — a host already resolved is not re-probed.
    func loadInstanceMetadata(forHost host: String) async {
        guard instanceMetadata[host] == nil else { return }
        guard let metadata = await dependencies.nodeInfoService.metadata(host: host) else { return }
        instanceMetadata[host] = metadata
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

    /// Subscription state derived from the account's real subscriptions: an
    /// in-flight request wins, then membership in ``subscribedUrls``, else idle. So
    /// a community the account is already subscribed to correctly reads `.subscribed`.
    func subscriptionState(for row: CommunityListRow) -> CommunitySubscriptionState {
        if inFlightRowIds.contains(row.id) { return .inFlight }
        if subscribedUrls.contains(row.communityUrl) { return .subscribed }
        return .idle
    }

    /// Toggle the subscription for `row`: subscribe when idle, unsubscribe when
    /// already subscribed. Signed-out accounts hit the sign-in gate; in-flight rows
    /// are ignored.
    func toggleSubscription(_ row: CommunityListRow) {
        guard isSignedIn else {
            onRequestSignIn()
            return
        }
        switch subscriptionState(for: row) {
        case .inFlight:
            return
        case .idle:
            setSubscribed(row, subscribe: true)
        case .subscribed:
            setSubscribed(row, subscribe: false)
        }
    }

    /// Subscribe to every community in `communities` that isn't subscribed yet
    /// (used by the starter-pack "Subscribe to all"). One sign-in gate for the
    /// whole batch.
    func subscribeToAll(_ communities: [CommunityListRow]) {
        guard isSignedIn else {
            onRequestSignIn()
            return
        }
        let pending = communities.filter { subscriptionState(for: $0) == .idle }
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

    /// Block `row` on the user's instance. Like Subscribe, the Explorer row is first
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
    /// and subscribed sets so the buttons reflect the change without waiting on the
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
                    subscribedUrls.insert(row.communityUrl)
                } else {
                    subscribedUrls.remove(row.communityUrl)
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
        trending = ExplorerCommunityDirectory.trending(in: allRows, limit: Self.railDepth)
        rising = ExplorerCommunityDirectory.rising(in: allRows, limit: Self.railDepth)
        instances = ExplorerCommunityDirectory.topInstances(in: allRows, limit: Self.railDepth)
        recomputeBecauseYouFollow()
    }

    private func recomputeBecauseYouFollow() {
        becauseYouFollow = ExplorerCommunityDirectory.becauseYouFollow(
            in: allRows,
            followedHosts: subscribedHosts,
            excludingUrls: subscribedUrls,
            limit: Self.railDepth
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
