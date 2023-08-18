//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class AccountViewController: UIViewController {
    typealias OwnDependencies =
        HasVoid
    typealias NestedDependencies =
        AccountListViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: - UI Properties

    lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: UIFont.systemFontSize + 15, weight: .light)
        label.textColor = UIColor.tertiaryLabel
        label.numberOfLines = 0
        label.text = "Account\nnot implemented"
        return label
    }()

    // MARK: - Functions

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
        tabBarItem.title = "Account"
        tabBarItem.image = UIImage(systemName: "person.crop.circle")!

        let accountsBarButtonItem = UIBarButtonItem(
            title: "Accounts",
            style: .plain,
            target: self,
            action: #selector(accountsTapped)
        )
        navigationItem.leftBarButtonItem = accountsBarButtonItem

        view.backgroundColor = .white

        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
    }

    @objc
    private func accountsTapped() {
        let accountListViewController = AccountListViewController(
            dependencies: dependencies.nested
        )
        let navigationController = UINavigationController(rootViewController: accountListViewController)
        present(navigationController, animated: true)
    }
}
