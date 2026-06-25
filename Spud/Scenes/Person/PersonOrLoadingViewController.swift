//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUtilKit
import UIKit

class PersonOrLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase
    typealias NestedDependencies =
        PersonLoadingViewController.Dependencies &
        PersonViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: - Public

    var contentViewController: PersonViewController? {
        currentViewController as? PersonViewController
    }

    // MARK: - Private

    private enum State {
        case person(personRowId: Int64)
        case load
    }

    private var state: State {
        didSet {
            stateChanged()
        }
    }

    private let serverPersonId: Components.Schemas.PersonID
    private let instance: InstanceActorId
    private let accountKeychainId: String
    private var currentViewController: UIViewController?

    // MARK: - Functions

    init(
        personId: Components.Schemas.PersonID,
        instance: InstanceActorId,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        serverPersonId = personId
        self.instance = instance
        self.accountKeychainId = accountKeychainId

        let appDatabase = self.dependencies.own.appDatabase
        if let personRowId = appDatabase.personRowIdSync(
            forKeychainId: accountKeychainId,
            personId: Int64(personId)
        ) {
            state = .person(personRowId: personRowId)
        } else {
            state = .load
        }

        super.init(nibName: nil, bundle: nil)

        stateChanged()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func stateChanged() {
        remove(child: currentViewController)
        currentViewController = nil

        let newViewController: UIViewController
        switch state {
        case let .person(personRowId):
            let contentViewController = PersonViewController(
                personRowId: personRowId,
                serverPersonId: serverPersonId,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            newViewController = contentViewController

        case .load:
            let loadingViewController = PersonLoadingViewController(
                serverPersonId: serverPersonId,
                instance: instance,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            newViewController = loadingViewController

            loadingViewController.didFinishLoading = { [weak self] personRowId in
                self?.state = .person(personRowId: personRowId)
            }
        }

        currentViewController = newViewController
        add(child: newViewController)
        addSubviewWithEdgeConstraints(child: newViewController)

        promoteContentIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        promoteContentIfNeeded()
    }

    /// Once the person is resolved, replace ourselves in the navigation stack
    /// with the `PersonViewController` so its navigation bar — the overflow
    /// menu, the sort button, and the title it sets from the loaded person —
    /// renders. A child view controller's `navigationItem` is ignored by UIKit,
    /// so hosting the content as a child (the way the loading state is hosted)
    /// would hide its entire navbar. The loading state stays an embedded child
    /// (it has no navbar to surface). The swap is deferred past any in-flight
    /// push so we never mutate the stack mid-transition.
    private func promoteContentIfNeeded() {
        guard case .person = state,
              let content = currentViewController as? PersonViewController,
              let navigationController,
              let index = navigationController.viewControllers.firstIndex(of: self)
        else { return }

        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.promoteContentIfNeeded()
            }
            return
        }

        remove(child: content)
        // While embedded it was pinned with edge constraints
        // (translatesAutoresizingMaskIntoConstraints = false); as a navigation
        // stack root UIKit frames the view via autoresizing, so restore that or
        // the content lays out to a zero frame and renders blank.
        content.view.translatesAutoresizingMaskIntoConstraints = true
        var stack = navigationController.viewControllers
        stack[index] = content
        navigationController.setViewControllers(stack, animated: false)
    }
}
