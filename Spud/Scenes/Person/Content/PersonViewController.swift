//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// The person profile content: an Apollo-style header pinned above a segmented
/// Posts / Comments list of the user's own content. Posts render as feed-style
/// rows and comments as comment-with-context rows (reusing the Search cells).
/// Tapping a post opens PostDetail; tapping a comment opens its post.
class PersonViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasImageService
    /// Spelled out as a concrete protocol composition rather than the child
    /// VCs' `Dependencies` typealiases to avoid a recursive typealias cycle
    /// (Person -> Community -> PostList -> PostDetail -> Person). This is the
    /// union those expand to; the live `DependencyContainer` conforms to all.
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

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: Private

    private let accountKeychainId: String
    private let viewModel: PersonViewModel

    private let headerView = PersonHeaderView()

    private var headerObservationTask: Task<Void, Never>?
    private var contentObservationTask: Task<Void, Never>?
    private var bannerImageTask: Task<Void, Never>?
    private var avatarImageTask: Task<Void, Never>?
    private var loadedBannerUrl: URL?
    private var loadedAvatarUrl: URL?

    private enum Section: Hashable {
        case content
    }

    private enum Item: Hashable {
        case post(SearchPostResult)
        case comment(SearchCommentResult)
    }

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: PersonContentTab.allCases.map(\.title))
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = viewModel.tab.rawValue
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.delegate = self
        tableView.register(SearchPostCell.self, forCellReuseIdentifier: SearchPostCell.reuseIdentifier)
        tableView.register(SearchCommentCell.self, forCellReuseIdentifier: SearchCommentCell.reuseIdentifier)
        return tableView
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Section, Item> = makeDataSource()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        return control
    }()

    // MARK: Functions

    init(
        personRowId: Int64,
        serverPersonId: Components.Schemas.PersonID,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        viewModel = PersonViewModel(
            personRowId: personRowId,
            serverPersonId: serverPersonId,
            accountKeychainId: accountKeychainId,
            accountService: dependencies.accountService,
            appDatabase: dependencies.appDatabase
        )

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        headerObservationTask?.cancel()
        contentObservationTask?.cancel()
        bannerImageTask?.cancel()
        avatarImageTask?.cancel()
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.linkTapped = { [weak self] url in
            self?.linkTapped(url)
        }

        tableView.refreshControl = refreshControl

        view.addSubview(headerView)
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            segmentedControl.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])

        let interaction = UIContextMenuInteraction(delegate: self)
        headerView.addInteraction(interaction)

        configureMessageButton()
    }

    /// A "Message" button is offered when the viewer is signed in and the
    /// profile is not their own. It opens the composer sheet targeting a new
    /// private message to this person.
    private func configureMessageButton() {
        guard !accountService.isSignedOut(forAccountKeychainId: accountKeychainId) else { return }
        let ownPersonId = appDatabase
            .accountOwnPersonIdsSync(forKeychainId: accountKeychainId)
            .map { Components.Schemas.PersonID($0.serverPersonId) }
        guard ownPersonId != viewModel.serverPersonId else { return }

        let messageButton = UIBarButtonItem(
            image: UIImage(systemName: "envelope"),
            style: .plain,
            target: self,
            action: #selector(messageTapped)
        )
        messageButton.accessibilityLabel = NSLocalizedString(
            "Message",
            comment: "Person profile message button accessibility label"
        )
        navigationItem.rightBarButtonItem = messageButton
    }

    @objc
    private func messageTapped() {
        Haptics.tap()
        let composer = ComposerViewController.makeSheet(
            target: .privateMessage(recipientId: viewModel.serverPersonId),
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        present(composer, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservations()
        viewModel.loadContent()
    }

    // MARK: Observation

    private func startObservations() {
        headerObservationTask?.cancel()
        contentObservationTask?.cancel()

        let viewModel = viewModel
        headerObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.title, viewModel.handle, viewModel.statsText, viewModel.bioMarkdown, viewModel.avatarUrl, viewModel.bannerUrl)
            }) {
                if Task.isCancelled { break }
                self?.applyHeader()
            }
        }
        contentObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.phase, viewModel.tab, viewModel.content.posts, viewModel.content.comments)
            }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
    }

    private func applyHeader() {
        navigationItem.title = viewModel.title

        headerView.configure(
            title: viewModel.title,
            handle: viewModel.handle,
            statsText: viewModel.statsText,
            bioMarkdown: viewModel.bioMarkdown
        )

        loadBannerIfNeeded(url: viewModel.bannerUrl)
        loadAvatarIfNeeded(url: viewModel.avatarUrl)
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

    private func loadAvatarIfNeeded(url: URL?) {
        guard let url, url != loadedAvatarUrl else { return }
        loadedAvatarUrl = url
        avatarImageTask?.cancel()
        avatarImageTask = Task { [weak self] in
            for await state in self?.imageService.fetch(url) ?? .never {
                if Task.isCancelled { return }
                if case let .ready(image) = state {
                    self?.headerView.setAvatarImage(image)
                }
            }
        }
    }

    // MARK: Rendering

    private func render() {
        switch viewModel.phase {
        case .loading:
            if !refreshControl.isRefreshing {
                loadingIndicator.startAnimating()
            }
            updateContentUnavailable(.none)
            applySnapshot([])
        case .loaded:
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
            applyContentSnapshot()
            updateContentUnavailable(
                viewModel.content.isEmpty(for: viewModel.tab) ? .empty : .none
            )
        case .error:
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
            applySnapshot([])
            updateContentUnavailable(.error)
        }
    }

    private func applyContentSnapshot() {
        let items: [Item]
        switch viewModel.tab {
        case .posts:
            items = viewModel.content.posts.map(Item.post)
        case .comments:
            items = viewModel.content.comments.map(Item.comment)
        }
        applySnapshot(items)
    }

    private func applySnapshot(_ items: [Item]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.content])
        snapshot.appendItems(items, toSection: .content)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private enum ContentUnavailable {
        case none
        case empty
        case error
    }

    private func updateContentUnavailable(_ state: ContentUnavailable) {
        switch state {
        case .none:
            contentUnavailableConfiguration = nil
        case .empty:
            var config = UIContentUnavailableConfiguration.empty()
            switch viewModel.tab {
            case .posts:
                config.image = UIImage(systemName: "doc.richtext")
                config.text = NSLocalizedString("No posts", comment: "Person profile empty posts state")
                config.secondaryText = NSLocalizedString(
                    "This user hasn't posted anything yet.",
                    comment: "Person profile empty posts message"
                )
            case .comments:
                config.image = UIImage(systemName: "text.bubble")
                config.text = NSLocalizedString("No comments", comment: "Person profile empty comments state")
                config.secondaryText = NSLocalizedString(
                    "This user hasn't commented anywhere yet.",
                    comment: "Person profile empty comments message"
                )
            }
            contentUnavailableConfiguration = config
        case .error:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "exclamationmark.triangle")
            config.text = NSLocalizedString("Couldn't load", comment: "Person profile error state title")
            config.secondaryText = NSLocalizedString(
                "Check your connection and pull to refresh.",
                comment: "Person profile error state message"
            )
            contentUnavailableConfiguration = config
        }
    }

    // MARK: Data source

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            switch item {
            case let .post(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchPostCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchPostCell
                cell.configure(with: result, imageService: imageService)
                return cell

            case let .comment(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchCommentCell
                cell.configure(with: result)
                return cell
            }
        }
    }

    // MARK: Actions

    @objc
    private func segmentChanged() {
        guard let tab = PersonContentTab(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        Haptics.tap()
        viewModel.tabChanged(tab)
    }

    @objc
    private func refreshTriggered() {
        viewModel.loadContent()
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

// MARK: - UITableViewDelegate

extension PersonViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        guard let window = view.window as? MainWindow else { return }

        switch item {
        case let .post(result):
            window.display(serverPostId: result.serverPostId, accountKeychainId: accountKeychainId)
        case let .comment(result):
            window.display(serverPostId: result.serverPostId, accountKeychainId: accountKeychainId)
        }
    }
}

// MARK: - Context menu

extension PersonViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let copyHandle = UIAction(
                title: NSLocalizedString("Copy handle", comment: "Person header context-menu action to copy the @user@instance handle"),
                image: UIImage(systemName: "doc.on.doc")
            ) { [weak self] _ in
                UIPasteboard.general.string = self?.viewModel.handle
                Haptics.tap()
            }
            return UIMenu(title: "", children: [copyHandle])
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
