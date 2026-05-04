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
        HasSiteService
    typealias NestedDependencies =
        LoginViewController.Dependencies &
        SiteListSiteViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var siteService: SiteServiceType {
        dependencies.own.siteService
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
    private var observationTask: Task<Void, Never>?

    private var searchController: UISearchController!

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

        // Seed with whatever's already in AppDatabase so the tableView is
        // populated by the time it appears.
        allRows = appDatabase.allSiteListRowsSync()
        applyFilter()
    }

    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self, appDatabase] in
            for await rows in appDatabase.observeAllSites() {
                guard let self else { return }
                allRows = rows
                applyFilter()
            }
        }
    }

    private func applyFilter() {
        if searchQuery.isEmpty {
            visibleRows = allRows
        } else {
            let needle = searchQuery.lowercased()
            visibleRows = allRows.filter { row in
                if row.hostname.lowercased().contains(needle) { return true }
                if let description = row.descriptionText?.lowercased(),
                   description.contains(needle)
                {
                    return true
                }
                return false
            }
        }
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        siteService.populateSiteListWithSuggestedInstancesIfNeeded()
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
        let loginViewController = LoginViewController(
            row: row,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(loginViewController, animated: true)
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
