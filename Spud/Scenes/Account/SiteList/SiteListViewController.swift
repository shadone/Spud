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

    /// The table's two sections: a single static "Add your own instance" row,
    /// then the Explorer directory. Kept as its own section (rather than a
    /// prepended directory row) so `visibleRows`/`indexPath.row` indexing for
    /// the directory never has to account for an offset.
    private enum Section: Int, CaseIterable {
        case addCustomInstance
        case directory
    }

    private static let addCustomInstanceReuseIdentifier = "AddCustomInstanceCell"

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var explorerService: ExplorerServiceType {
        dependencies.own.explorerService
    }

    // MARK: UI Properties

    var cancelBarButtonItem: UIBarButtonItem!

    /// Whether to show the leading "Cancel" item (which dismisses). True when
    /// presented modally (the add-account flow); false when pushed onto an
    /// existing nav stack (onboarding), where the system back button is wanted.
    private let showsCancelButton: Bool

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self
        tableView.dataSource = self

        tableView.register(SiteListSiteCell.self, forCellReuseIdentifier: SiteListSiteCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.addCustomInstanceReuseIdentifier)

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

    init(dependencies: Dependencies, showsCancelButton: Bool = true) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.showsCancelButton = showsCancelButton

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
        if showsCancelButton {
            cancelBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(cancelTapped)
            )
            navigationItem.leftBarButtonItems = [cancelBarButtonItem]
        }

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
        // Offer only languages that still match the OTHER active filters
        // (registration-open / hide-NSFW), so every choice yields >= 1 instance.
        // Title each by its localized display name and order by that name, not the
        // raw code, so the menu reads "English / German / ..." not "EN / DE / ...".
        let languageCodes = ExplorerInstanceDirectory
            .availableLanguages(in: allRows, matching: filter)
            .sorted { lhs, rhs in
                Self.languageDisplayName(lhs)
                    .localizedStandardCompare(Self.languageDisplayName(rhs)) == .orderedAscending
            }
        let languageActions = languageCodes.map { code in
            UIAction(
                title: Self.languageDisplayName(code),
                state: filter.language == code ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                filter.language = code
                refreshMenus()
                applyFilter()
            }
        }
        let languageMenu = UIMenu(title: "Language", children: [anyLanguage] + languageActions)

        return UIMenu(title: "Filter", children: [toggles, languageMenu])
    }

    /// Human-readable name for a language code ("en" -> "English"), falling back
    /// to the uppercased code when the system has no localized name for it.
    private static func languageDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized
            ?? code.uppercased()
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

        // The picker doesn't refresh on every appearance — that's governed by the
        // Community Data settings. But on first launch, when the directory is still
        // the bundled seed (possibly months old) and the user is here to log in,
        // refresh the instance list once if stale so they choose from current
        // servers. Later opens (adding or switching accounts) don't auto-refresh.
        if appDatabase.explorerInstancesAreSeedOnlySync() {
            Task { [explorerService] in
                await explorerService.refreshIfStale(maxAge: ExplorerService.defaultMaxAge)
            }
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
        switch Section(rawValue: indexPath.section) {
        case .addCustomInstance:
            tableView.deselectRow(at: indexPath, animated: true)
            let entry = CustomInstanceEntryViewController(dependencies: dependencies.nested)
            navigationController?.pushViewController(entry, animated: true)

        case .directory:
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

        case nil:
            break
        }
    }
}

// MARK: - Table View DataSource

extension SiteListViewController: UITableViewDataSource {
    func numberOfSections(in _: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .addCustomInstance: 1
        case .directory: visibleRows.count
        case nil: 0
        }
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .addCustomInstance:
            return addCustomInstanceCell(for: tableView, at: indexPath)

        case .directory, nil:
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

    /// The static top-of-list row: an SF Symbol + "Add your own instance" +
    /// disclosure chevron, styled like a plain system settings row via
    /// `UIListContentConfiguration` (native Dynamic Type / a11y for free).
    /// Pushes `CustomInstanceEntryViewController` for a Lemmy instance not in
    /// the bundled/Explorer directory (e.g. a private, non-federated server).
    private func addCustomInstanceCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: Self.addCustomInstanceReuseIdentifier,
            for: indexPath
        )

        var content = UIListContentConfiguration.cell()
        content.text = NSLocalizedString("Add your own instance", comment: "SiteList add-custom-instance row")
        content.image = UIImage(systemName: "plus.circle")
        content.imageProperties.tintColor = tableView.tintColor
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "site-list-add-custom-instance"

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
