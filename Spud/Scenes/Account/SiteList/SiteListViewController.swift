//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudDataKit
import UIKit

private let logger = Logger.app

class SiteListViewController: UIViewController {
    typealias OwnDependencies =
        HasAppDatabase &
        HasExplorerService
    typealias NestedDependencies =
        InstanceDetailViewController.Dependencies &
        SiteListSiteViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var explorerService: ExplorerServiceType {
        dependencies.own.explorerService
    }

    // MARK: UI Properties

    var cancelBarButtonItem: UIBarButtonItem!

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self
        tableView.dataSource = self

        tableView.register(SiteListSiteCell.self, forCellReuseIdentifier: SiteListSiteCell.reuseIdentifier)

        return tableView
    }()

    // MARK: Private

    private var allRows: [SiteListRow] = []
    private var visibleRows: [SiteListRow] = []
    private var searchQuery: String = ""
    private var sort: ExplorerInstanceSort = .recommended
    private var filter = ExplorerInstanceFilter()
    private var observationTask: Task<Void, Never>?

    private var searchController: UISearchController!
    private var sortBarButtonItem: UIBarButtonItem!
    private var filterBarButtonItem: UIBarButtonItem!

    // MARK: Functions

    init(dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    deinit {
        observationTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        cancelBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        navigationItem.leftBarButtonItems = [cancelBarButtonItem]

        sortBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "arrow.up.arrow.down"),
            primaryAction: nil,
            menu: makeSortMenu()
        )
        filterBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            primaryAction: nil,
            menu: makeFilterMenu()
        )
        navigationItem.rightBarButtonItems = [filterBarButtonItem, sortBarButtonItem]

        navigationItem.title = "Choose an instance"

        view.backgroundColor = .white

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none

        navigationItem.searchController = searchController

        // Seed with the cached Explorer instance directory so the tableView is
        // populated (ranked by Explorer score) by the time it appears.
        allRows = appDatabase.explorerSiteListRowsSync()
        refreshMenus()
        applyFilter()
    }

    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self, appDatabase] in
            for await rows in appDatabase.observeExplorerSiteListRows() {
                guard let self else { return }
                allRows = rows
                refreshMenus()
                applyFilter()
            }
        }
    }

    private func applyFilter() {
        visibleRows = ExplorerInstanceDirectory.apply(
            to: allRows,
            query: searchQuery,
            filter: filter,
            sort: sort
        )
        tableView.reloadData()
    }

    private func makeSortMenu() -> UIMenu {
        let actions = ExplorerInstanceSort.allCases.map { option in
            UIAction(title: option.title, state: option == sort ? .on : .off) { [weak self] _ in
                guard let self else { return }
                sort = option
                refreshMenus()
                applyFilter()
            }
        }
        return UIMenu(title: "Sort by", children: actions)
    }

    private func makeFilterMenu() -> UIMenu {
        let registration = UIAction(
            title: "Registration open",
            state: filter.registrationOpenOnly ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            filter.registrationOpenOnly.toggle()
            refreshMenus()
            applyFilter()
        }
        let nsfw = UIAction(
            title: "Hide NSFW",
            state: filter.hideNsfw ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            filter.hideNsfw.toggle()
            refreshMenus()
            applyFilter()
        }
        let toggles = UIMenu(title: "", options: .displayInline, children: [registration, nsfw])

        let anyLanguage = UIAction(
            title: "Any language",
            state: filter.language == nil ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            filter.language = nil
            refreshMenus()
            applyFilter()
        }
        let languageActions = ExplorerInstanceDirectory.availableLanguages(in: allRows).map { code in
            UIAction(title: code.uppercased(), state: filter.language == code ? .on : .off) { [weak self] _ in
                guard let self else { return }
                filter.language = code
                refreshMenus()
                applyFilter()
            }
        }
        let languageMenu = UIMenu(title: "Language", children: [anyLanguage] + languageActions)

        return UIMenu(title: "Filter", children: [toggles, languageMenu])
    }

    private func refreshMenus() {
        sortBarButtonItem.menu = makeSortMenu()
        filterBarButtonItem.menu = makeFilterMenu()
        filterBarButtonItem.image = UIImage(
            systemName: filter.isActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Task { [explorerService] in
            await explorerService.refreshIfStale(maxAge: ExplorerService.defaultMaxAge)
        }
        startObserving()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        observationTask?.cancel()
        observationTask = nil
    }

    @objc
    private func cancelTapped() {
        dismiss(animated: true)
    }
}

// MARK: - Table View Delegate

extension SiteListViewController: UITableViewDelegate {
    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = visibleRows[indexPath.row]
        // Show the instance detail ("before you commit") screen. Fall back to
        // login directly if the directory record isn't available.
        if let record = appDatabase.explorerInstanceSync(baseurl: row.hostname) {
            let detail = InstanceDetailViewController(record: record, dependencies: dependencies.nested)
            navigationController?.pushViewController(detail, animated: true)
        } else {
            let login = LoginViewController(row: row, dependencies: dependencies.nested)
            navigationController?.pushViewController(login, animated: true)
        }
    }
}

// MARK: - Table View DataSource

extension SiteListViewController: UITableViewDataSource {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        visibleRows.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SiteListSiteCell.reuseIdentifier,
            for: indexPath
        ) as! SiteListSiteCell

        let viewModel = SiteListSiteViewModel(
            row: visibleRows[indexPath.row],
            dependencies: dependencies.nested
        )
        cell.configure(with: viewModel)

        return cell
    }
}

// MARK: - UISearchController Delegate

extension SiteListViewController: UISearchControllerDelegate {
    func didDismissSearchController(_: UISearchController) {
        searchQuery = ""
        applyFilter()
    }
}

// MARK: - UISearchResultsUpdating

extension SiteListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text?
            .trimmingCharacters(in: .whitespaces) ?? ""
        applyFilter()
    }
}
