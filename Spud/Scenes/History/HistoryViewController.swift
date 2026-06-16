//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

@MainActor
class HistoryViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService
    typealias NestedDependencies = PostDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var appearanceService: AppearanceServiceType {
        dependencies.own.appearanceService
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    // MARK: Private

    private let viewModel: HistoryViewModel
    private var rowsByServerPostId: [Int64: PostListRow] = [:]
    private var observationTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?

    // MARK: UI Properties

    enum Section: Hashable {
        case posts
    }

    enum Item: Hashable {
        case post(serverPostId: Int64)
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.delegate = self
        tableView.register(PostListPostCell.self, forCellReuseIdentifier: PostListPostCell.reuseIdentifier)
        return tableView
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString("No posts yet", comment: "History empty state message")
        label.isHidden = true
        return label
    }()

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            NSLocalizedString("Read", comment: "History segment: posts opened by the user"),
            NSLocalizedString("Seen", comment: "History segment: all posts encountered"),
            NSLocalizedString("Saved", comment: "History segment: saved posts"),
        ])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = NSLocalizedString("Search history", comment: "History search bar placeholder")
        return sc
    }()

    // MARK: Functions

    init(accountKeychainId: String, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        viewModel = HistoryViewModel(accountKeychainId: accountKeychainId)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
        searchDebounceTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        view.backgroundColor = .systemBackground
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        setupDataSource()
        setupSegmentedControl()
        startObservation()
    }

    private func setupSegmentedControl() {
        navigationItem.titleView = segmentedControl
    }

    private func setupDataSource() {
        let appearance = appearanceService
        let imageService = imageService
        let postContentDetector = dependencies.own.postContentDetectorService

        dataSource = UITableViewDiffableDataSource<Section, Item>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, item in
            guard case let .post(serverPostId) = item,
                  let row = self?.rowsByServerPostId[serverPostId]
            else {
                return UITableViewCell()
            }

            let cell = tableView.dequeueReusableCell(
                withIdentifier: PostListPostCell.reuseIdentifier,
                for: indexPath
            ) as! PostListPostCell

            let viewModel = PostListPostViewModel(
                row: row,
                appearance: appearance,
                postContentDetector: postContentDetector
            )
            cell.configure(with: viewModel, imageService: imageService)
            return cell
        }
    }

    private func applySnapshot(order serverPostIds: [Int64]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.posts])
        let items = serverPostIds.map { Item.post(serverPostId: $0) }
        snapshot.appendItems(items, toSection: .posts)
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)

        emptyStateLabel.isHidden = !serverPostIds.isEmpty
    }

    private func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observeHistoryRows(
                forKeychainId: viewModel.accountKeychainId,
                mode: viewModel.mode,
                searchQuery: viewModel.searchQuery
            ) {
                if Task.isCancelled { break }
                rowsByServerPostId = Dictionary(uniqueKeysWithValues: rows.map { ($0.serverPostId, $0) })
                applySnapshot(order: rows.map(\.serverPostId))
            }
        }
    }

    @objc
    private func segmentChanged() {
        let modes: [HistoryMode] = [.read, .seen, .saved]
        let index = segmentedControl.selectedSegmentIndex
        guard modes.indices.contains(index) else { return }
        viewModel.mode = modes[index]
        startObservation()
    }
}

// MARK: - UITableViewDelegate

extension HistoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { return }
        guard let window = view.window as? MainWindow else { return }
        window.display(
            serverPostId: Components.Schemas.PostID(serverPostId),
            accountKeychainId: viewModel.accountKeychainId
        )
    }
}

// MARK: - UISearchResultsUpdating

extension HistoryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            if Task.isCancelled { return }
            viewModel.searchText = text
            startObservation()
        }
    }
}
