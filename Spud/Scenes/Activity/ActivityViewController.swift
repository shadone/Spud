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
class ActivityViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase
    typealias NestedDependencies = PostDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: Private

    private let accountKeychainId: String
    private let viewModel: ActivityViewModel

    private var observationTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?

    // MARK: UI

    private lazy var filterBarView: ActivityFilterBarView = {
        let v = ActivityFilterBarView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.onToggleFilter = { [weak self] filter in
            self?.viewModel.toggleFilter(filter)
        }
        return v
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.rowHeight = UITableView.automaticDimension
        tv.delegate = self
        tv.register(ActivityPostCell.self, forCellReuseIdentifier: ActivityPostCell.reuseIdentifier)
        tv.register(ActivityCommentCell.self, forCellReuseIdentifier: ActivityCommentCell.reuseIdentifier)
        return tv
    }()

    private lazy var emptyStateLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        l.text = NSLocalizedString("No activity yet", comment: "Activity empty state")
        l.isHidden = true
        return l
    }()

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = NSLocalizedString("Search activity", comment: "Activity search bar placeholder")
        return sc
    }()

    private var dataSource: UITableViewDiffableDataSource<String, String>!

    // MARK: Lookup

    private var itemById: [String: ActivityItem] = [:]

    // MARK: Functions

    init(accountKeychainId: String, dependencies: Dependencies) {
        self.accountKeychainId = accountKeychainId
        self.dependencies = (own: dependencies, nested: dependencies)

        let db = dependencies.appDatabase
        let serverPersonId = db.accountPersonServerIdSync(forKeychainId: accountKeychainId)
        let personRowId = serverPersonId.flatMap {
            db.personRowIdSync(forKeychainId: accountKeychainId, personId: $0)
        }
        let lemmyService = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId).lemmyService
        let authoredSource: AuthoredActivitySource? = serverPersonId.map {
            LemmyAuthoredActivitySource(
                lemmyService: lemmyService,
                serverPersonId: Components.Schemas.PersonID($0)
            )
        }
        let coordinator = ActivityCoordinator(
            appDatabase: db,
            personRowId: personRowId,
            authoredSource: authoredSource
        )
        let accountId = db.accountRowIdSync(forKeychainId: accountKeychainId) ?? 0
        viewModel = ActivityViewModel(coordinator: coordinator, accountId: accountId)

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
        view.backgroundColor = Theme.background
        title = NSLocalizedString("Activity", comment: "Activity screen title")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true

        setupLayout()
        setupDataSource()
        startObservation()
        viewModel.start()
    }

    // MARK: Private

    private func setupLayout() {
        let filterContainer = UIView()
        filterContainer.translatesAutoresizingMaskIntoConstraints = false
        filterContainer.addSubview(filterBarView)

        NSLayoutConstraint.activate([
            filterBarView.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor),
            filterBarView.trailingAnchor.constraint(equalTo: filterContainer.trailingAnchor),
            filterBarView.topAnchor.constraint(equalTo: filterContainer.topAnchor),
            filterBarView.bottomAnchor.constraint(equalTo: filterContainer.bottomAnchor),
            filterContainer.heightAnchor.constraint(equalToConstant: 50),
        ])

        tableView.tableHeaderView = filterContainer

        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    private func setupDataSource() {
        dataSource = UITableViewDiffableDataSource<String, String>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, itemId in
            self?.cell(tableView: tableView, indexPath: indexPath, itemId: itemId)
        }
        dataSource.defaultRowAnimation = .fade
    }

    private func cell(
        tableView: UITableView,
        indexPath: IndexPath,
        itemId: String
    ) -> UITableViewCell {
        guard let item = itemById[itemId] else {
            return UITableViewCell()
        }
        switch item.object {
        case let .post(post):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: ActivityPostCell.reuseIdentifier,
                for: indexPath
            ) as! ActivityPostCell
            cell.configure(with: item, post: post)
            return cell
        case let .comment(comment):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: ActivityCommentCell.reuseIdentifier,
                for: indexPath
            ) as! ActivityCommentCell
            cell.configure(with: item, comment: comment)
            return cell
        }
    }

    private func startObservation() {
        observationTask?.cancel()
        let viewModel = viewModel
        observationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.items, viewModel.activeFilters, viewModel.loadState)
            }) {
                if Task.isCancelled { break }
                self?.applySnapshot()
            }
        }
    }

    private func applySnapshot() {
        let items = viewModel.items

        itemById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        filterBarView.activeFilters = viewModel.activeFilters

        let grouped = groupedByDay(items)
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        for (section, sectionItems) in grouped {
            snapshot.appendSections([section])
            snapshot.appendItems(sectionItems.map(\.id), toSection: section)
        }
        dataSource.apply(snapshot, animatingDifferences: true)

        emptyStateLabel.isHidden = !items.isEmpty
    }

    private func groupedByDay(_ items: [ActivityItem]) -> [(section: String, items: [ActivityItem])] {
        var buckets: [(label: String, date: Date, items: [ActivityItem])] = []
        var labelToIndex: [String: Int] = [:]

        for item in items {
            let label = dayLabel(for: item.occurredAt)
            if let idx = labelToIndex[label] {
                buckets[idx].items.append(item)
            } else {
                labelToIndex[label] = buckets.count
                buckets.append((label: label, date: item.occurredAt, items: [item]))
            }
        }

        return buckets.map { (section: $0.label, items: $0.items) }
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return NSLocalizedString("Today", comment: "Activity day section: today")
        }
        if Calendar.current.isDateInYesterday(date) {
            return NSLocalizedString("Yesterday", comment: "Activity day section: yesterday")
        }
        return DateFormatter.activityDaySection.string(from: date)
    }

    private func navigate(to item: ActivityItem) {
        switch item.object {
        case let .post(post):
            (view.window as? MainWindow)?.display(
                serverPostId: Components.Schemas.PostID(post.serverPostId),
                accountKeychainId: accountKeychainId
            )
        case let .comment(comment):
            guard let serverPostId = comment.serverPostId else { return }
            (view.window as? MainWindow)?.display(
                serverPostId: Components.Schemas.PostID(serverPostId),
                accountKeychainId: accountKeychainId,
                scrollToCommentId: Components.Schemas.CommentID(comment.serverCommentId)
            )
        }
    }
}

// MARK: - UITableViewDelegate

extension ActivityViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let itemId = dataSource.itemIdentifier(for: indexPath),
              let item = itemById[itemId] else { return }
        navigate(to: item)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title = dataSource.snapshot().sectionIdentifiers[section]
        let header = UITableViewHeaderFooterView()
        header.textLabel?.text = title
        return header
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.height
        if contentHeight > frameHeight, offsetY > contentHeight - frameHeight - 200 {
            viewModel.loadMore()
        }
    }
}

// MARK: - UISearchResultsUpdating

extension ActivityViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchQuery = searchController.searchBar.text ?? ""
        viewModel.onSearchQueryChanged()
    }
}

// MARK: - DateFormatter

private extension DateFormatter {
    static let activityDaySection: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
