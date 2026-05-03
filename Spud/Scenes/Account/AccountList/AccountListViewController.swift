//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import OSLog
import SpudDataKit
import UIKit

private let logger = Logger.app

class AccountListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasDataStore
    typealias NestedDependencies =
        SiteListViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var dataStore: DataStoreType {
        dependencies.own.dataStore
    }

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    // MARK: UI Properties

    var cancelBarButtonItem: UIBarButtonItem!
    var addAccountBarButtonItem: UIBarButtonItem!

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self

        tableView.register(AccountListAccountCell.self, forCellReuseIdentifier: AccountListAccountCell.reuseIdentifier)

        return tableView
    }()

    // MARK: Private

    var accountsFRC: NSFetchedResultsController<LemmyAccount>?
    private var dataSource: UITableViewDiffableDataSource<Int, NSManagedObjectID>!

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

        addAccountBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addAccountTapped)
        )

        updateBarButtonItems()

        navigationItem.title = "Accounts"

        view.backgroundColor = .white

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupDataSource()
        setupFRC()
    }

    private func setupDataSource() {
        let mainContext = dataStore.mainContext
        dataSource = UITableViewDiffableDataSource<Int, NSManagedObjectID>(
            tableView: tableView
        ) { tableView, indexPath, objectID in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: AccountListAccountCell.reuseIdentifier,
                for: indexPath
            ) as! AccountListAccountCell

            guard let account = try? mainContext.existingObject(with: objectID) as? LemmyAccount else {
                logger.assertionFailure("Failed to resolve account for objectID \(objectID)")
                return cell
            }

            cell.configure(with: AccountListAccountViewModel(account: account))
            return cell
        }
    }

    private func setupFRC() {
        // reset the old FRC in case we are reusing the same VC for a new post.
        accountsFRC?.delegate = nil

        let request = LemmyAccount.fetchRequest() as NSFetchRequest<LemmyAccount>
        request.predicate = NSPredicate(
            format: "isServiceAccount == false"
        )
        request.fetchBatchSize = 100
        request.relationshipKeyPathsForPrefetching = ["site"]
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LemmyAccount.isSignedOutAccountType, ascending: true),
        ]

        accountsFRC = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: dataStore.mainContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        accountsFRC?.delegate = self
    }

    private func execFRC() {
        do {
            try accountsFRC?.performFetch()
        } catch {
            logger.error("Failed to fetch accounts: \(String(describing: error), privacy: .public)")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        execFRC()
    }

    private func updateBarButtonItems() {
        if isEditing {
            navigationItem.leftBarButtonItems = [addAccountBarButtonItem]
        } else {
            navigationItem.leftBarButtonItems = [cancelBarButtonItem]
        }
        navigationItem.rightBarButtonItems = [editButtonItem]
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.isEditing = editing
        updateBarButtonItems()
    }

    @objc
    private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc
    private func addAccountTapped() {
        setEditing(false, animated: true)

        let siteListViewController = SiteListViewController(
            dependencies: dependencies.nested
        )
        let navigationController = UINavigationController(rootViewController: siteListViewController)
        present(navigationController, animated: true)
    }
}

// MARK: - FRC helpers

extension AccountListViewController {
    func account(at indexPath: IndexPath) -> LemmyAccount? {
        guard let objectID = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return try? dataStore.mainContext.existingObject(with: objectID) as? LemmyAccount
    }
}

// MARK: - Table View Delegate

extension AccountListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let account = account(at: indexPath) else { return }
        accountService.setDefaultAccount(account)
        dismiss(animated: true)
    }
}

// MARK: - Core Data

extension AccountListViewController: NSFetchedResultsControllerDelegate {
    nonisolated func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        let typedSnapshot = snapshot as NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
        MainActor.assumeIsolated {
            dataSource.apply(typedSnapshot, animatingDifferences: true)
        }
    }
}
