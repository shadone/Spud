//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

class SubscriptionsViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        PostListViewController.Dependencies
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self
        tableView.dataSource = self

        tableView.register(SubscriptionsSpecialCommunityCell.self, forCellReuseIdentifier: SubscriptionsSpecialCommunityCell.reuseIdentifier)

        return tableView
    }()

    // MARK: Private

    enum SpecialCommunity: Int {
        case subscribed
        case local
        case all

        init(from indexPath: IndexPath) {
            assert(indexPath.section == 0)
            switch indexPath.row {
            case 0: self = .subscribed
            case 1: self = .local
            case 2: self = .all
            default: fatalError()
            }
        }
    }

    private let account: LemmyAccount

    // MARK: Functions

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        self.account = account

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .white

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - UITableView Delegate

extension SubscriptionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let lemmyService = accountService.lemmyService(for: account)
        let feed: LemmyFeed

        let sortType = account.accountInfo?.defaultSortType ?? .hot

        switch SpecialCommunity(from: indexPath) {
        case .subscribed:
            feed = lemmyService.createFeed(.frontpage(
                listingType: .subscribed,
                sortType: sortType
            ))

        case .local:
            feed = lemmyService.createFeed(.frontpage(
                listingType: .local,
                sortType: sortType
            ))

        case .all:
            feed = lemmyService.createFeed(.frontpage(
                listingType: .all,
                sortType: sortType
            ))
        }

        let postListVC = PostListViewController(feed: feed, dependencies: dependencies.nested)
        navigationController?.pushViewController(postListVC, animated: true)
    }
}

// MARK: - UITableView DataSource

extension SubscriptionsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SubscriptionsSpecialCommunityCell.reuseIdentifier,
            for: indexPath
        ) as! SubscriptionsSpecialCommunityCell

        switch SpecialCommunity(from: indexPath) {
        case .subscribed:
            cell.icon = UIImage(systemName: "newspaper")!
            cell.titleText = "Subscribed"
            cell.subtitleText = "Posts from your subscriptions"

        case .local:
            cell.icon = UIImage(systemName: "house")!
            cell.titleText = "Local"
            cell.subtitleText = "Posts from your home instance"

        case .all:
            cell.icon = UIImage(systemName: "rectangle.stack")!
            cell.titleText = "All"
            cell.subtitleText = "Posts from all federated instances"
        }

        return cell
    }
}
