//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// Resolve-then-show wrapper for the in-app instance screen, reached by tapping
/// an instance name anywhere in the app.
///
/// When the host is in the bundled Lemmy Explorer directory (or was already
/// resolved this session), the ``InstanceExploreViewController`` is shown
/// immediately. Otherwise this shows a brief spinner while it probes the host's
/// `/api/v3/site`: a Lemmy-API-compatible server (including PieFed) yields a
/// synthesized record and opens in-app; anything else (non-Lemmy / unreachable)
/// falls back to the browser and pops this wrapper off the stack.
final class InstanceOrLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase
    typealias NestedDependencies =
        InstanceExploreViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private let host: String
    private let accountKeychainId: String

    private var resolveTask: Task<Void, Never>?
    private var didResolve = false

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(
        host: String,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.host = host
        self.accountKeychainId = accountKeychainId
        super.init(nibName: nil, bundle: nil)
        navigationItem.title = host
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        resolveTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        // `InstanceRouter` only pushes this wrapper for hosts that are NOT in the
        // directory or session cache, so this screen always probes the network.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didResolve, resolveTask == nil else { return }
        loadingIndicator.startAnimating()
        resolveTask = Task { @MainActor [weak self] in
            await self?.resolve()
        }
    }

    /// Probe the host's `/api/v3/site`. On success, synthesize a directory
    /// record, cache it for the session, and swap to the instance screen. On
    /// failure (non-Lemmy / unreachable / cancelled), open the browser and pop
    /// this wrapper.
    private func resolve() async {
        guard let instance = InstanceActorId(from: "https://\(host)") else {
            openBrowserAndPop()
            return
        }

        let keychainId = accountService.accountForSignedOut(
            forInstance: instance,
            isServiceAccount: true
        )
        let service = accountService.scope(forAccountKeychainId: keychainId).lemmyService

        do {
            // Cap the probe so a host that accepts the connection but never
            // answers doesn't strand the user on the spinner (URLSession's
            // default request timeout is a full 60s).
            let response = try await withTimeout(.seconds(15)) {
                try await service.getSiteInfo()
            }
            guard !Task.isCancelled else { return }
            let record = ExplorerInstanceRecord.synthesized(from: response, host: host)
            ResolvedInstanceCache.shared.store(record)
            showInstance(record: record, animated: false)
        } catch {
            guard !Task.isCancelled else { return }
            logger.info("Instance probe failed for \(self.host, privacy: .public); opening browser. \(String(describing: error), privacy: .public)")
            openBrowserAndPop()
        }
    }

    /// Replace ourselves in the navigation stack with the resolved
    /// ``InstanceExploreViewController`` so its navigation bar (title, actions)
    /// renders. A child view controller's `navigationItem` is ignored by UIKit,
    /// so hosting the content as a child would hide its navbar.
    private func showInstance(record: ExplorerInstanceRecord, animated: Bool) {
        guard !didResolve else { return }
        didResolve = true
        resolveTask?.cancel()

        let content = InstanceExploreViewController(
            record: record,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )

        guard
            let navigationController,
            let index = navigationController.viewControllers.firstIndex(of: self)
        else {
            // Not on a nav stack (shouldn't happen) — present modally as a
            // last resort so the tap is not silently dropped.
            present(UINavigationController(rootViewController: content), animated: animated)
            return
        }

        var stack = navigationController.viewControllers
        stack[index] = content
        navigationController.setViewControllers(stack, animated: animated)
    }

    private func openBrowserAndPop() {
        // Signal that the tap did something other than open the in-app screen
        // (the host isn't a Lemmy-API instance), matching the feedback the
        // call sites gave before routing through here.
        Haptics.warning()
        if let url = URL(string: "https://\(host)") {
            UIApplication.shared.open(url)
        }
        // Pop ourselves so the user is left where they were, not on a dead
        // spinner screen.
        if let navigationController,
           navigationController.viewControllers.last === self
        {
            navigationController.popViewController(animated: true)
        }
    }
}
