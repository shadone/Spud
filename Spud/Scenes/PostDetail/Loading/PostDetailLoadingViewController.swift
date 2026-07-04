//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import UIKit

class PostDetailLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: - Public

    /// Fires once the post row appears in AppDatabase, with the resolved
    /// server post id ready for the content view controller to consume.
    var didFinishLoading: ((Components.Schemas.PostID) -> Void)?

    /// Fires when the post cannot be loaded because the server reports it gone
    /// (`couldnt_find_post`). The parent swaps in the unavailable placeholder.
    var didFail: ((PostUnavailableReason) -> Void)?

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

    private let accountKeychainId: String
    private let serverPostId: Components.Schemas.PostID
    private var observationTask: Task<Void, Never>?

    // MARK: - Functions

    init(
        serverPostId: Components.Schemas.PostID,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId
        self.serverPostId = serverPostId

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
        view.backgroundColor = Theme.background
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadingIndicator.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if await fetchPostInfoReportingNotFound() {
                didFail?(.unavailable)
                return
            }
            await notifyIfRowAvailable()
        }
    }

    /// Returns `true` when the post is gone server-side (`couldnt_find_post`);
    /// other errors are logged and return `false` (fall through to row check).
    private func fetchPostInfoReportingNotFound() async -> Bool {
        do {
            try await dependencies.own.accountService
                .scope(forAccountKeychainId: accountKeychainId)
                .lemmyService
                .fetchPostInfo(serverPostId: serverPostId)
            return false
        } catch {
            if ContentNotFound.matchesPost(error) { return true }
            alertService.handle(error, for: .fetchPostInfo)
            return false
        }
    }

    private func notifyIfRowAvailable() async {
        // After fetchPostInfo succeeds the GRDB mirror has written the row.
        // Resolve it and notify the parent. If for some reason it hasn't
        // landed yet, fall through silently — the parent will keep showing
        // the spinner and the user can pop the screen.
        if appDatabase.postRowIdSync(
            forKeychainId: accountKeychainId,
            serverPostId: Int64(serverPostId)
        ) != nil {
            didFinishLoading?(serverPostId)
        }
    }
}
