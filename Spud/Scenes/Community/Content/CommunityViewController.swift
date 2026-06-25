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
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// The community screen content: an Apollo-style header pinned above the
/// community's post feed. The feed is the existing `PostListViewController`
/// (driven by `FeedType.community`), embedded as a child below the header.
class CommunityViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppearanceService &
        HasImageService
    /// Spelled out as a concrete protocol composition rather than
    /// `PostListViewController.Dependencies` to avoid a recursive typealias
    /// cycle (PostList -> PostDetail -> Community -> PostList). This is the same
    /// union those typealiases expand to, and the live `DependencyContainer`
    /// conforms to all of them.
    typealias NestedDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService &
        HasReachabilityMonitor &
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountScope: AccountScope {
        dependencies.own.accountService.scope(forAccountKeychainId: accountKeychainId)
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    // MARK: Private

    private let accountKeychainId: String
    private let viewModel: CommunityViewModel

    private let headerView = CommunityHeaderView()
    private var feedViewController: PostListViewController?
    /// Retained so the share sheet's iPad popover can anchor to it.
    private var overflowBarButtonItem: UIBarButtonItem?

    private var observationTask: Task<Void, Never>?
    private var bannerImageTask: Task<Void, Never>?
    private var iconImageTask: Task<Void, Never>?
    private var loadedBannerUrl: URL?
    private var loadedIconUrl: URL?

    // MARK: Functions

    init(
        accountRowId: Int64,
        serverCommunityId: Components.Schemas.CommunityID,
        feed: FeedHandle,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        viewModel = CommunityViewModel(
            accountRowId: accountRowId,
            serverCommunityId: serverCommunityId,
            appDatabase: dependencies.appDatabase
        )

        let feedViewController = PostListViewController(
            feed: feed,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        self.feedViewController = feedViewController

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
        bannerImageTask?.cancel()
        iconImageTask?.cancel()
    }

    private func setup() {
        view.backgroundColor = Theme.background

        let newPostButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(newPostTapped)
        )
        // Group 1: state-dependent actions (subscribe + favorite), deferred so
        // they reflect live subscription / favorite state each time the menu
        // opens. Group 2: mute + block. Group 3: sharing. Inline groups keep the
        // three visually separated.
        let stateGroup = UIMenu(options: .displayInline, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.subscribeMenuActions() ?? [])
            },
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.favoriteMenuActions() ?? [])
            },
        ])
        let moderationGroup = UIMenu(options: .displayInline, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.muteMenuActions() ?? [])
            },
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.blockMenuActions() ?? [])
            },
        ])
        let sharingGroup = UIMenu(options: .displayInline, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.sharingMenuActions() ?? [])
            },
        ])
        let overflowButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [stateGroup, moderationGroup, sharingGroup])
        )
        overflowButton.accessibilityLabel = NSLocalizedString(
            "More",
            comment: "Community overflow menu accessibility label"
        )
        overflowBarButtonItem = overflowButton

        headerView.imageService = imageService
        headerView.subscribeTapped = { [weak self] in
            self?.toggleSubscribed()
        }
        headerView.onBodyLinkTapped = { [weak self] url in
            self?.routeInternalLink(MarkdownInternalLink.resolve(url) ?? url)
        }
        headerView.onBodyImageTapped = { [weak self] url, altText, _ in
            guard let self else { return }
            presentMediaViewer(
                imageUrl: url,
                thumbnailUrl: nil,
                preloadedImage: nil,
                altText: altText,
                dependencies: dependencies.own
            )
        }
        headerView.onBodyVideoTapped = { [weak self] url in
            self?.presentVideoPlayer(url: url)
        }
        headerView.onBodyAudioTapped = { [weak self] url in
            self?.presentVideoPlayer(url: url)
        }
        headerView.onInstanceTapped = { [weak self] in
            self?.openInstanceDetail()
        }
        // The header is the feed table's scrolling header, which doesn't re-measure
        // itself; whenever the description's height changes (async markdown parse
        // landing, spoiler toggle, or an inline image loading) ask the feed to
        // re-lay-out the header so the change is reflected.
        headerView.onDescriptionHeightChanged = { [weak self] in
            self?.feedViewController?.layoutScrollingHeaderIfNeeded()
        }

        let interaction = UIContextMenuInteraction(delegate: self)
        headerView.addInteraction(interaction)

        guard let feedViewController else { return }
        add(child: feedViewController)
        let feedView = feedViewController.view!
        feedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(feedView)

        NSLayoutConstraint.activate([
            feedView.topAnchor.constraint(equalTo: view.topAnchor),
            feedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Host the community header inside the feed's scroll view (as its table
        // header) so it scrolls away with the posts instead of staying pinned at
        // the top. Headers can be tall (description, rules), so pinning would eat
        // too much fixed space.
        feedViewController.setScrollingHeaderView(headerView)

        // Surface the embedded feed's existing sort-order pull-down in this
        // controller's navbar. A child VC's own `navigationItem` is ignored, so
        // the host has to place the child's button. The feed builds it in its
        // `init` (via `setup()`), so it's non-nil by the time `add(child:)`
        // above has run. Order (first element = right-most): overflow, then sort,
        // then compose.
        let sortButton = feedViewController.feedSortMenuBarButtonItem
        sortButton.accessibilityLabel = NSLocalizedString(
            "Sort posts",
            comment: "Community feed sort menu accessibility label"
        )
        navigationItem.rightBarButtonItems = [overflowButton, sortButton, newPostButton]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservation()
        // Resolve whether this community is already blocked so the menu shows
        // the correct Block / Unblock label.
        refreshBlockState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateUserActivity()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        userActivity?.resignCurrent()
        userActivity = nil
    }

    /// Vends a Handoff/Spotlight/Prediction activity for this community, keyed by
    /// `!name@instance` so it resolves without a network round-trip.
    private func updateUserActivity() {
        guard
            !viewModel.name.isEmpty,
            let actorId = viewModel.actorId,
            let url = URL(string: actorId),
            let instance = InstanceActorId(from: url)
        else { return }
        let routingURL = URL.SpudInternalLink.community(name: viewModel.name, instance: instance).url
        let activity = SpudUserActivity.viewCommunity(routingURL: routingURL, name: viewModel.name)
        userActivity = activity
        activity.becomeCurrent()
    }

    /// Resolves whether this community is currently blocked, from the server's
    /// `getSite` block list. No-op for signed-out accounts.
    private func refreshBlockState() {
        guard !accountScope.isSignedOut else { return }
        let serverCommunityId = viewModel.serverCommunityId
        Task { [weak self] in
            guard let self else { return }
            do {
                let blocked = try await accountScope
                    .lemmyService
                    .fetchBlockedList()
                if Task.isCancelled { return }
                viewModel.isBlocked = blocked.communities.contains { $0.serverCommunityId == serverCommunityId }
                viewModel.blockStateKnown = true
            } catch {
                logger.error("Refresh community block state failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Builds the Block / Unblock action for the overflow menu, reflecting the
    /// current `isBlocked` state.
    private func blockMenuActions() -> [UIMenuElement] {
        let blocked = viewModel.isBlocked
        let blockAction = UIAction(
            title: blocked
                ? NSLocalizedString("Unblock community", comment: "Overflow action to unblock a community")
                : NSLocalizedString("Block community", comment: "Overflow action to block a community"),
            image: UIImage(systemName: blocked ? "hand.raised.slash" : "hand.raised"),
            attributes: blocked ? [] : .destructive
        ) { [weak self] _ in
            self?.toggleBlockCommunity()
        }
        return [blockAction]
    }

    private func toggleBlockCommunity() {
        guard !accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block a community")
            )
            return
        }

        let blocking = !viewModel.isBlocked
        if blocking {
            presentDestructiveConfirmation(
                title: String(
                    format: NSLocalizedString("Block %@?", comment: "Block community confirmation title"),
                    viewModel.qualifiedName.isEmpty ? viewModel.title : viewModel.qualifiedName
                ),
                message: NSLocalizedString(
                    "You won't see posts from this community. You can unblock it later.",
                    comment: "Block community confirmation message"
                ),
                confirmTitle: NSLocalizedString("Block", comment: "Block community confirm button"),
                sourceItem: navigationItem.rightBarButtonItems?.first
            ) { [weak self] in
                Task { await self?.applyBlockCommunity(true) }
            }
        } else {
            Task { await applyBlockCommunity(false) }
        }
    }

    /// Builds the Mute / Unmute element for the overflow menu, reflecting the
    /// current mute state. Muting is a local view concern (not server-backed),
    /// so it isn't sign-in gated. When unmuted, offers a timed-duration submenu;
    /// when muted, a single Unmute action.
    private func muteMenuActions() -> [UIMenuElement] {
        guard let actorId = viewModel.actorId else { return [] }
        let muted = appDatabase.isCommunityMutedSync(
            forKeychainId: accountKeychainId,
            communityActorId: actorId
        )
        if muted {
            return [UIAction(
                title: NSLocalizedString("Unmute community", comment: "Overflow action to unmute a community"),
                image: UIImage(systemName: "bell")
            ) { [weak self] _ in
                self?.unmuteCommunity()
            }]
        }
        let durationActions = MuteDuration.allCases.map { duration in
            UIAction(title: duration.menuTitle) { [weak self] _ in
                self?.muteCommunity(duration: duration)
            }
        }
        return [UIMenu(
            title: NSLocalizedString("Mute community", comment: "Overflow action to mute a community"),
            image: UIImage(systemName: "bell.slash"),
            children: durationActions
        )]
    }

    private func muteCommunity(duration: MuteDuration) {
        guard let actorId = viewModel.actorId else { return }
        Haptics.tap()
        appDatabase.muteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: actorId,
            until: duration.until
        )
    }

    private func unmuteCommunity() {
        guard let actorId = viewModel.actorId else { return }
        Haptics.tap()
        appDatabase.unmuteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: actorId
        )
    }

    /// Builds the Subscribe / Unsubscribe action for the overflow menu,
    /// reflecting the current subscription state. Mirrors the context-menu
    /// action; the underlying `toggleSubscribed()` is sign-in gated.
    private func subscribeMenuActions() -> [UIMenuElement] {
        let subscribed = viewModel.subscribed.isSubscribed
        return [UIAction(
            title: subscribed
                ? NSLocalizedString("Unsubscribe", comment: "Overflow action to unsubscribe from a community")
                : NSLocalizedString("Subscribe", comment: "Overflow action to subscribe to a community"),
            image: UIImage(systemName: subscribed ? "minus.circle" : "plus.circle")
        ) { [weak self] _ in
            self?.toggleSubscribed()
        }]
    }

    /// Builds the Add to Favorites / Remove from Favorites action for the
    /// overflow menu, reflecting the current favorite state. Favorites are a
    /// local concern (like muting), so this isn't sign-in gated.
    private func favoriteMenuActions() -> [UIMenuElement] {
        guard let actorId = viewModel.actorId else { return [] }
        let favorited = appDatabase.isCommunityFavoritedSync(
            forKeychainId: accountKeychainId,
            communityActorId: actorId
        )
        return [UIAction(
            title: favorited
                ? NSLocalizedString("Remove from Favorites", comment: "Overflow action to unfavorite a community")
                : NSLocalizedString("Add to Favorites", comment: "Overflow action to favorite a community"),
            image: UIImage(systemName: favorited ? "star.slash" : "star")
        ) { [weak self] _ in
            self?.toggleFavorite()
        }]
    }

    private func toggleFavorite() {
        guard let actorId = viewModel.actorId else { return }
        Haptics.tap()
        let favorited = appDatabase.isCommunityFavoritedSync(
            forKeychainId: accountKeychainId,
            communityActorId: actorId
        )
        if favorited {
            appDatabase.unfavoriteCommunitySync(
                forKeychainId: accountKeychainId,
                communityActorId: actorId
            )
        } else {
            appDatabase.favoriteCommunitySync(
                forKeychainId: accountKeychainId,
                communityActorId: actorId
            )
        }
    }

    /// Builds the sharing actions (Copy Link, Share, Open in Browser) for the
    /// overflow menu. Omitted when the community has no valid actor-id URL.
    private func sharingMenuActions() -> [UIMenuElement] {
        guard
            let actorId = viewModel.actorId,
            let url = URL(string: actorId)
        else { return [] }

        let copyLink = UIAction(
            title: NSLocalizedString("Copy Link", comment: "Overflow action to copy a community's link"),
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in
            Haptics.tap()
            UIPasteboard.general.url = url
        }
        let share = UIAction(
            title: NSLocalizedString("Share…", comment: "Overflow action to share a community"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.presentShareSheet(for: url, sourceItem: self?.overflowBarButtonItem)
        }
        let openInBrowser = UIAction(
            title: NSLocalizedString("Open in Browser", comment: "Overflow action to open a community in the browser"),
            image: UIImage(systemName: "safari")
        ) { _ in
            Haptics.tap()
            UIApplication.shared.open(url)
        }
        return [copyLink, share, openInBrowser]
    }

    private func applyBlockCommunity(_ blocked: Bool) async {
        Haptics.tap()
        let previous = viewModel.isBlocked
        viewModel.isBlocked = blocked
        do {
            try await accountScope
                .lemmyService
                .setBlocked(serverCommunityId: viewModel.serverCommunityId, blocked: blocked)
            viewModel.blockStateKnown = true
            Haptics.success()
            // The server now filters this community's posts out of feed fetches;
            // reload the embedded feed so blocked content disappears.
            feedViewController?.reloadFeed()
        } catch {
            viewModel.isBlocked = previous
            alertService.handle(error, for: .setBlockedCommunity)
        }
    }

    private func startObservation() {
        observationTask?.cancel()
        let viewModel = viewModel
        observationTask = Task { @MainActor [weak self] in
            // Touch every property `applyViewModel` renders so a change to any
            // of them (e.g. `subscribed` flipping after a subscribe) re-fires
            // the observation. `withObservationTracking` only re-tracks the
            // properties read inside the access closure.
            for await _ in ObservationStream.values(of: {
                (
                    viewModel.hasLoaded,
                    viewModel.title,
                    viewModel.qualifiedName,
                    viewModel.subscribersText,
                    viewModel.postsText,
                    viewModel.descriptionMarkdown,
                    viewModel.iconUrl,
                    viewModel.bannerUrl,
                    viewModel.subscribed
                )
            }) {
                if Task.isCancelled { break }
                self?.applyViewModel()
            }
        }
    }

    private func applyViewModel() {
        guard viewModel.hasLoaded else { return }

        navigationItem.title = viewModel.title

        headerView.configure(
            title: viewModel.title,
            qualifiedName: viewModel.qualifiedName,
            subscribersText: viewModel.subscribersText,
            postsText: viewModel.postsText,
            vitalityText: viewModel.vitalityText,
            descriptionMarkdown: viewModel.descriptionMarkdown,
            subscribed: viewModel.subscribed
        )
        // The header's height changes once real content (description, rules,
        // counts) is filled in; re-measure so the feed's table header tracks it.
        feedViewController?.layoutScrollingHeaderIfNeeded()

        loadBannerIfNeeded(url: viewModel.bannerUrl)
        loadIconIfNeeded(url: viewModel.iconUrl)
    }

    private func loadBannerIfNeeded(url: URL?) {
        guard let url, url != loadedBannerUrl else { return }
        loadedBannerUrl = url
        bannerImageTask?.cancel()
        bannerImageTask = Task { [weak self] in
            for await state in self?.imageService.fetch(url) ?? .never {
                if Task.isCancelled { return }
                if case let .ready(image) = state {
                    self?.headerView.setBannerImage(image)
                }
            }
        }
    }

    private func loadIconIfNeeded(url: URL?) {
        guard let url, url != loadedIconUrl else { return }
        loadedIconUrl = url
        iconImageTask?.cancel()
        iconImageTask = Task { [weak self] in
            for await state in self?.imageService.fetch(url) ?? .never {
                if Task.isCancelled { return }
                if case let .ready(image) = state {
                    self?.headerView.setIconImage(image)
                }
            }
        }
    }

    // MARK: Actions

    /// Presents the new-post composer pre-filled with this community, gating on
    /// sign-in.
    @objc
    private func newPostTapped() {
        guard !accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to post", comment: "Sign-in gate title when a signed-out user tries to create a post")
            )
            return
        }

        Haptics.tap()
        let accountKeychainId = accountKeychainId
        let composer = NewPostViewController.makeSheet(
            serverCommunityId: viewModel.serverCommunityId,
            initialCommunityName: viewModel.qualifiedName.isEmpty ? viewModel.name : viewModel.qualifiedName,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.own
        ) { [weak self] clientToken in
            guard let window = self?.view.window as? MainWindow else { return }
            window.displayPending(clientToken: clientToken, accountKeychainId: accountKeychainId)
        }
        present(composer, animated: true)
    }

    /// Toggles subscription state against the currently observed value,
    /// gating on sign-in.
    private func toggleSubscribed() {
        guard !accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to subscribe", comment: "Sign-in gate title when a signed-out user tries to subscribe to a community")
            )
            return
        }

        let currentlySubscribed = viewModel.subscribed.isSubscribed
        Task { await setSubscribed(!currentlySubscribed) }
    }

    private func setSubscribed(_ subscribed: Bool) async {
        Haptics.tap()
        do {
            try await accountScope
                .lemmyService
                .setSubscribed(serverCommunityId: viewModel.serverCommunityId, subscribed: subscribed)
        } catch {
            alertService.handle(error, for: .setSubscribed)
        }
    }

    private func openInstanceDetail() {
        guard
            let actorId = viewModel.actorId,
            let url = URL(string: actorId),
            let host = url.host
        else { return }
        guard let record = appDatabase.explorerInstanceSync(baseurl: host) else {
            if let instanceURL = URL(string: "https://\(host)") { UIApplication.shared.open(instanceURL) }
            return
        }
        let vc = InstanceExploreViewController(
            record: record,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - InternalLinkRouting

extension CommunityViewController: InternalLinkRouting {
    var linkRouterAppDatabase: AppDatabase {
        appDatabase
    }

    var linkRouterLemmyService: LemmyServiceType {
        accountScope.lemmyService
    }

    func routeToPerson(personId: Components.Schemas.PersonID, instance: InstanceActorId) {
        let vc = PersonOrLoadingViewController(
            personId: personId,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    func routeToCommunity(name: String, instance: InstanceActorId) {
        let vc = CommunityOrLoadingViewController(
            communityName: name,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    func routeToPost(postId: Components.Schemas.PostID, instance _: InstanceActorId) {
        guard let window = view.window as? MainWindow else {
            logger.error("No MainWindow available to display post")
            return
        }
        window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
    }

    func routeToInstance(_ instance: InstanceActorId) {
        guard let record = appDatabase.explorerInstanceSync(baseurl: instance.host) else {
            if let url = instance.url { UIApplication.shared.open(url) }
            return
        }
        let vc = InstanceExploreViewController(
            record: record,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    func routeToExternal(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - Context menu

extension CommunityViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let subscribed = viewModel.subscribed.isSubscribed
            let action = UIAction(
                title: subscribed
                    ? NSLocalizedString("Unsubscribe", comment: "Context-menu action to unsubscribe from a community")
                    : NSLocalizedString("Subscribe", comment: "Context-menu action to subscribe to a community"),
                image: UIImage(systemName: subscribed ? "minus.circle" : "plus.circle")
            ) { [weak self] _ in
                self?.toggleSubscribed()
            }
            let blocked = viewModel.isBlocked
            let blockAction = UIAction(
                title: blocked
                    ? NSLocalizedString("Unblock community", comment: "Context-menu action to unblock a community")
                    : NSLocalizedString("Block community", comment: "Context-menu action to block a community"),
                image: UIImage(systemName: blocked ? "hand.raised.slash" : "hand.raised"),
                attributes: blocked ? [] : .destructive
            ) { [weak self] _ in
                self?.toggleBlockCommunity()
            }
            return UIMenu(title: "", children: [action, blockAction])
        }
    }
}

private extension AsyncStream {
    /// An empty stream, used as a fallback when `self` has already been
    /// deallocated by the time the image task starts.
    static var never: AsyncStream<Element> {
        AsyncStream { $0.finish() }
    }
}
