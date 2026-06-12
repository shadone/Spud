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
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
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
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(newPostTapped)
        )

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.subscribeTapped = { [weak self] in
            self?.toggleSubscribed()
        }
        headerView.linkTapped = { [weak self] url in
            self?.linkTapped(url)
        }

        view.addSubview(headerView)

        guard let feedViewController else { return }
        add(child: feedViewController)
        let feedView = feedViewController.view!
        feedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(feedView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            feedView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            feedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let interaction = UIContextMenuInteraction(delegate: self)
        headerView.addInteraction(interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservation()
    }

    private func startObservation() {
        observationTask?.cancel()
        let viewModel = viewModel
        observationTask = Task { @MainActor [weak self] in
            // Touch every property `applyViewModel` renders so a change to any
            // of them (e.g. `subscribed` flipping after a subscribe) re-fires
            // the observation. `withObservationTracking` only re-tracks the
            // properties read inside the access closure.
            for await _ in Self.values(of: {
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
            descriptionMarkdown: viewModel.descriptionMarkdown,
            subscribed: viewModel.subscribed
        )

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
        guard !accountService.isSignedOut(forAccountKeychainId: accountKeychainId) else {
            Haptics.warning()
            presentErrorAlert(
                title: NSLocalizedString("Sign in to post", comment: "Title of the alert shown when a signed-out user tries to create a post"),
                message: NSLocalizedString(
                    "You need to be signed in to an account to create posts.",
                    comment: "Body of the alert shown when a signed-out user tries to create a post"
                )
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
        ) { [weak self] serverPostId in
            guard let window = self?.view.window as? MainWindow else { return }
            window.display(serverPostId: serverPostId, accountKeychainId: accountKeychainId)
        }
        present(composer, animated: true)
    }

    /// Toggles subscription state against the currently observed value,
    /// gating on sign-in.
    private func toggleSubscribed() {
        guard !accountService.isSignedOut(forAccountKeychainId: accountKeychainId) else {
            Haptics.warning()
            presentErrorAlert(
                title: NSLocalizedString("Sign in to subscribe", comment: "Title of the alert shown when a signed-out user tries to subscribe to a community"),
                message: NSLocalizedString(
                    "You need to be signed in to an account to subscribe to communities.",
                    comment: "Body of the alert shown when a signed-out user tries to subscribe to a community"
                )
            )
            return
        }

        let currentlySubscribed = viewModel.subscribed.isSubscribed
        Task { await setSubscribed(!currentlySubscribed) }
    }

    private func setSubscribed(_ subscribed: Bool) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: accountKeychainId)
                .setSubscribed(serverCommunityId: viewModel.serverCommunityId, subscribed: subscribed)
        } catch {
            alertService.handle(error, for: .setSubscribed)
        }
    }

    private func linkTapped(_ url: URL) {
        switch url.spud {
        case let .person(personId, instance):
            let vc = PersonOrLoadingViewController(
                personId: personId,
                instance: instance,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(vc, animated: true)

        case let .community(name, instance):
            let vc = CommunityOrLoadingViewController(
                communityName: name,
                instance: instance,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(vc, animated: true)

        case .post, .none:
            UIApplication.shared.open(url)
        }
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
            return UIMenu(title: "", children: [action])
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

private extension CommunityViewController {
    /// Tiny shim mirroring `PostListViewController.values(of:)`: turns an
    /// Observable property into an AsyncStream via `withObservationTracking`.
    @MainActor
    static func values<Value: Sendable>(
        of access: @escaping @MainActor () -> Value
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let scheduler = CommunityObservationScheduler<Value>(
                continuation: continuation,
                access: access
            )
            scheduler.observe()
        }
    }
}

@MainActor
private final class CommunityObservationScheduler<Value: Sendable>: Sendable {
    private let continuation: AsyncStream<Value>.Continuation
    private let access: @MainActor () -> Value

    init(
        continuation: AsyncStream<Value>.Continuation,
        access: @escaping @MainActor () -> Value
    ) {
        self.continuation = continuation
        self.access = access
    }

    func observe() {
        let value = withObservationTracking {
            access()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        continuation.yield(value)
    }
}
