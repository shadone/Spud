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
            instanceActorId: instance.actorId,
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

        add(child: newViewController)
        addSubviewWithEdgeConstraints(child: newViewController)
    }
}
