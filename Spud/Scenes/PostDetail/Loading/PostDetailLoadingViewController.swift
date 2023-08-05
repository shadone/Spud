//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import SpudDataKit
import UIKit
import os.log

class PostDetailLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasDataStore &
        HasAlertService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType { dependencies.own.accountService }
    private var alertService: AlertServiceType { dependencies.own.alertService }
    private var dataStore: DataStoreType { dependencies.own.dataStore }

    // MARK: - Public

    var didFinishLoading: ((LemmyPostInfo) -> Void)?

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

        // TODO: find a better way to get LemmyPost object if exists or create new otherwise.
        // e.g. something like
        // dataStore.getOrCreate(postId: postId)
        let context = dataStore.mainContext
        let request = LemmyPost.fetchRequest(postId: postId, account: account)
        let results = try! context.fetch(request)
        let post = results.first!

        accountService
            .lemmyService(for: account)
            .fetchPostInfo(postId: post.objectID)
            .sink(
                receiveCompletion: alertService.errorHandler(for: .fetchPostInfo),
                receiveValue: { [weak self] postInfo in
                    self?.didFinishLoading?(postInfo)
                }
            )
            .store(in: &disposables)
    }
}
