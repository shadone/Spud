//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import LemmyKit

class PostListViewController: UIViewController {
    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.dataSource = self

        tableView.register(PostListCell.self, forCellReuseIdentifier: PostListCell.reuseIdentifier)

        return tableView
    }()

    init() {
        super.init(nibName: nil, bundle: nil)

        setup()
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var lemmyService: LemmyServiceType?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let tchncs = URL(string: "https://discuss.tchncs.de")!

        let accountService = AppDelegate.shared.dependencies.accountService

        let account = accountService.accountForSignedOut(instanceUrl: tchncs)
        let lemmyService = accountService.lemmyService(for: account)
        self.lemmyService = lemmyService

        let feed = lemmyService.createFeed(.frontpage(listingType: .local, sortType: .active))
        Task {
            try await lemmyService.fetchFeed(feedId: feed.objectID, page: nil)
        }
    }
}

extension PostListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        5
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: PostListCell.reuseIdentifier,
            for: indexPath
        ) as! PostListCell

        return cell
    }
}
