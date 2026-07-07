//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

class PersonLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: - Public

    /// Fires once the person row appears in AppDatabase, with the resolved
    /// row id ready for the content view controller to consume.
    var didFinishLoading: ((Int64) -> Void)?

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
        label.accessibilityIdentifier = "loading"
        return label
    }()

    // MARK: Private

    private let serverPersonId: Components.Schemas.PersonID
    private let instance: InstanceActorId
    private let accountKeychainId: String
    private var observationTask: Task<Void, Never>?

    // MARK: - Functions

    init(
        serverPersonId: Components.Schemas.PersonID,
        instance: InstanceActorId,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.serverPersonId = serverPersonId
        self.instance = instance
        self.accountKeychainId = accountKeychainId

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
            guard let self, await fetchPersonInfo() else { return }
            await waitForRowToAppear()
        }
    }

    /// Fetches the person's details from the account's home instance and imports
    /// the resulting row into GRDB, unless the instance's API doesn't support
    /// person profiles (Lemmy 1.0's v3 compat shim - `InstanceCapability
    /// .personProfiles`), in which case a terminal `UIContentUnavailableConfiguration`
    /// is shown instead and `false` is returned.
    ///
    /// Reads `scope.capabilities` once (a live per-account DB read; see
    /// `AccountScope`'s doc comment) rather than on separate accesses. Returns
    /// `true` when the fetch was attempted (regardless of its outcome) so the
    /// caller knows whether to proceed to `waitForRowToAppear()` - when gated,
    /// that must NOT run: it would resolve `didFinishLoading` and let
    /// `PersonOrLoadingViewController` swap this loading screen out for the
    /// content VC, contradicting the terminal gated state (the loading VC stays
    /// on the nav stack; see Task 7's `InboxViewController` gated-state
    /// precedent for the same explain-don't-hide shape).
    @discardableResult
    private func fetchPersonInfo() async -> Bool {
        let scope = accountService.scope(forAccountKeychainId: accountKeychainId)
        guard scope.capabilities.can(.personProfiles) else {
            showGatedState(host: scope.instanceActorId?.hostWithPort)
            return false
        }

        do {
            try await scope.lemmyService.fetchPersonInfo(serverPersonId: serverPersonId)
        } catch {
            alertService.handle(error, for: .fetchPersonInfo)
        }
        return true
    }

    /// Renders the terminal capability-gate state explaining that the account's
    /// home instance doesn't support fetching person profiles yet. Hides the
    /// spinner/label stack - this state is terminal, so nothing else on this
    /// screen will transition afterward.
    private func showGatedState(host: String?) {
        loadingIndicator.stopAnimating()
        stackView.isHidden = true

        var config = UIContentUnavailableConfiguration.empty()
        let copy = CapabilityGateCopy.copy(for: .personProfiles, host: host)
        // "tray.slash" doesn't exist as an SF Symbol (verified against this SDK);
        // `clock.badge.questionmark` matches the Inbox gated state (Task 7) and
        // reads as "not yet available", matching the copy's framing.
        config.image = UIImage(systemName: "clock.badge.questionmark")
        config.text = copy.title
        config.secondaryText = copy.message
        contentUnavailableConfiguration = config
    }

    private func waitForRowToAppear() async {
        // After fetchPersonInfo succeeds the GRDB mirror has written the row.
        // Resolve it and notify the parent. If for some reason it hasn't
        // landed yet, fall through silently — the parent will keep showing
        // the spinner and the user can pop the screen.
        if let personRowId = appDatabase.personRowIdSync(
            forKeychainId: accountKeychainId,
            personId: Int64(serverPersonId)
        ) {
            didFinishLoading?(personRowId)
        }
    }
}
