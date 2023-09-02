//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import SpudDataKit
import UIKit

private let logger = Logger(.app)

class SiteListViewController: UIViewController {
    typealias OwnDependencies =
        HasDataStore &
        HasSiteService
    typealias NestedDependencies =
        LoginViewController.Dependencies &
        SiteListSiteViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var dataStore: DataStoreType { dependencies.own.dataStore }
    var siteService: SiteServiceType { dependencies.own.siteService }

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

    private var fetchRequest: NSFetchRequest<LemmySite>!
    private var sitesFRC: NSFetchedResultsController<LemmySite>!

    private var searchController: UISearchController!

    // MARK: Functions

    init(dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        super.init(nibName: nil, bundle: nil)

        setup()
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

        setupFRC()
    }

    private func setupFRC() {
        // reset the old FRC in case we are reusing the same VC for a new post.
        sitesFRC?.delegate = nil

        let request = LemmySite.fetchRequest() as NSFetchRequest<LemmySite>
        request.fetchBatchSize = 100
        request.relationshipKeyPathsForPrefetching = ["siteInfo"]
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LemmySite.createdAt, ascending: true),
        ]

        sitesFRC = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: dataStore.mainContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        sitesFRC?.delegate = self
    }

    private func execFRC() {
        do {
            try sitesFRC?.performFetch()
        } catch {
            logger.error("Failed to fetch sites: \(String(describing: error), privacy: .public)")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        execFRC()
        siteService.populateSiteListWithSuggestedInstancesIfNeeded()
    }

    @objc
    private func cancelTapped() {
        dismiss(animated: true)
    }
}

// MARK: - FRC helpers

extension SiteListViewController {
    var numberOfSites: Int {
        sitesFRC?.sections?[0].numberOfObjects ?? 0
    }

    func site(at index: Int) -> LemmySite {
        guard
            let site = sitesFRC?.sections?[0].objects?[index] as? LemmySite
        else {
            fatalError()
        }
        return site
    }
}

// MARK: - Table View Delegate

extension SiteListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let site = site(at: indexPath.row)
        let loginViewController = LoginViewController(
            site: site,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(loginViewController, animated: true)
    }
}

// MARK: - Table View DataSource

extension SiteListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        numberOfSites
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SiteListSiteCell.reuseIdentifier,
            for: indexPath
        ) as! SiteListSiteCell

        let site = site(at: indexPath.row)
        let viewModel = SiteListSiteViewModel(
            site: site,
            dependencies: dependencies.nested
        )
        cell.configure(with: viewModel)

        return cell
    }
}

// MARK: - Core Data

extension SiteListViewController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }

    func controller(
        _: NSFetchedResultsController<NSFetchRequestResult>,
        didChange _: Any,
        at indexPath: IndexPath?,
        for type: NSFetchedResultsChangeType,
        newIndexPath: IndexPath?
    ) {
        switch type {
        case .insert:
            guard let newIndexPath else { fatalError() }
            tableView.insertRows(at: [newIndexPath], with: .fade)

        case .delete:
            guard let indexPath else { fatalError() }
            tableView.deleteRows(at: [indexPath], with: .fade)

        case .update:
            guard let indexPath else { fatalError() }

            guard let cell = tableView.cellForRow(at: indexPath) else { return }
            guard let cell = cell as? SiteListSiteCell else { fatalError() }

            let site = site(at: indexPath.row)
            let viewModel = SiteListSiteViewModel(
                site: site,
                dependencies: dependencies.nested
            )
            cell.configure(with: viewModel)

        case .move:
            logger.assertionFailure()

        @unknown default:
            logger.assertionFailure()
        }
    }
}

// MARK: - UISearchController Delegate

extension SiteListViewController: UISearchControllerDelegate {
    func didDismissSearchController(_ searchController: UISearchController) {
        sitesFRC.fetchRequest.predicate = nil

        execFRC()
        tableView.reloadData()
    }
}

// MARK: - UISearchResultsUpdating

extension SiteListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let whitespaceCharacterSet = CharacterSet.whitespaces

        let query = searchController.searchBar.text?
            .trimmingCharacters(in: whitespaceCharacterSet) ?? ""

        let instanceUrl = NSPredicate(
            format: "instance.actorIdRawValue CONTAINS[cd] %@",
            query
        )
        let descriptionText = NSPredicate(
            format: "siteInfo.descriptionText CONTAINS[cd] %@",
            query
        )

        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            instanceUrl,
            descriptionText,
        ])
        sitesFRC.fetchRequest.predicate = predicate

        execFRC()
        tableView.reloadData()
    }
}
