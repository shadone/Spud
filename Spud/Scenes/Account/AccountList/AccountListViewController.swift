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

class AccountListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase
    typealias NestedDependencies =
        SiteListViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
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

    private var dataSource: UITableViewDiffableDataSource<Int, Int64>!
    private var rowsByAccountId: [Int64: AccountListRow] = [:]
    private var observationTask: Task<Void, Never>?

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

    deinit {
        observationTask?.cancel()
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
    }

    private func setupDataSource() {
        dataSource = UITableViewDiffableDataSource<Int, Int64>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, accountRowId in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: AccountListAccountCell.reuseIdentifier,
                for: indexPath
            ) as! AccountListAccountCell

            guard let row = self?.rowsByAccountId[accountRowId] else {
                logger.assertionFailure("Missing AccountListRow for accountId \(accountRowId)")
                return cell
            }

            cell.configure(with: AccountListAccountViewModel(row: row))
            return cell
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startObserving()
    }

    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [appDatabase] in
            for await rows in appDatabase.observeAccountListRows() {
                if Task.isCancelled { break }
                await MainActor.run { self.apply(rows: rows) }
            }
        }
    }

    private func apply(rows: [AccountListRow]) {
        rowsByAccountId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int64>()
        snapshot.appendSections([0])
        snapshot.appendItems(rows.map(\.id), toSection: 0)
        // Reload items so cells re-bind when row contents change but the id list doesn't.
        snapshot.reloadItems(rows.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
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

// MARK: - Table View Delegate

extension AccountListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard
            let accountRowId = dataSource.itemIdentifier(for: indexPath),
            let row = rowsByAccountId[accountRowId]
        else { return }

        accountService.setDefaultAccount(forAccountKeychainId: row.accountKeychainId)
        dismiss(animated: true)
    }
}
