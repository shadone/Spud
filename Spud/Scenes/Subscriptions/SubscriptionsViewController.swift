//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import SpudDataKit
import SwiftUI
import UIKit

class SubscriptionsViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        SubscriptionsViewModel.Dependencies &
        PostListViewController.Dependencies
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    private let viewModel: SubscriptionsViewModel
    private let account: LemmyAccount

    // MARK: Functions

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        self.account = account

        self.viewModel = SubscriptionsViewModel(
            account: account,
            dependencies: self.dependencies.nested
        )

        super.init(nibName: nil, bundle: nil)

        setup()
        bindViewModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        let contentVC = UIHostingController(rootView: SubscriptionsView(viewModel: self.viewModel))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)
    }

    private func bindViewModel() {
        viewModel.outputs.feedRequested
            .sink { [weak self] feed in
                self?.display(feed: feed)
            }
            .store(in: &disposables)
    }

    private func display(feed: LemmyFeed) {
        let postListVC = PostListViewController(feed: feed, dependencies: dependencies.nested)
        navigationController?.pushViewController(postListVC, animated: true)
    }
}
