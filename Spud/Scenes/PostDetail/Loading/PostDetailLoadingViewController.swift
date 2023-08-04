//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import UIKit
import os.log

class PostDetailLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: - Public

    var didFinishLoading: ((LemmyPost) -> Void)?

    // MARK: - Private

    lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8

        stackView.addArrangedSubview(loadingIndicator)
        stackView.addArrangedSubview(label)

        return stackView
    }()

    lazy var loadingIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: UIFont.systemFontSize + 15, weight: .light)
        label.textColor = UIColor.tertiaryLabel
        label.text = "Loading…"
        return label
    }()

    // MARK: Private

    private let account: LemmyAccount
    private let postId: PostId
    private var disposables = Set<AnyCancellable>()

    // MARK: - Functions

    init(postId: PostId, account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.account = account
        self.postId = postId

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .systemBackground
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        loadingIndicator.startAnimating()

        accountService
            .lemmyService(for: account)
            .fetchPost(postId: postId)
            .sink { complete in
                switch complete {
                case let .failure(error):
                    os_log("Failed to fetch post: %{public}@",
                           log: .app, type: .error,
                           String(describing: error))
                case .finished:
                    break
                }
            } receiveValue: { [weak self] post in
                self?.didFinishLoading?(post)
            }
            .store(in: &disposables)
    }
}
