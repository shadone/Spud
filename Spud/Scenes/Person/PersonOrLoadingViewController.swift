//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import SpudDataKit
import SpudUtilKit
import UIKit

class PersonOrLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasDataStore &
        HasSiteService
    typealias NestedDependencies =
        PersonLoadingViewController.Dependencies &
        PersonViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: - Public

    var contentViewController: PersonViewController? {
        currentViewController as? PersonViewController
    }

    // MARK: - Private

    private let viewModel: PersonOrLoadingViewModelType

    private enum State {
        case person(LemmyPersonInfo)
        case load(LemmyPerson)
    }

    private var state: State {
        didSet {
            stateChanged()
        }
    }

    private let account: LemmyAccount
    private var currentViewController: UIViewController?
    private var disposables = Set<AnyCancellable>()

    // MARK: - Functions

    init(
        personId: PersonId,
        instance: InstanceActorId,
        account: LemmyAccount,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.account = account

        let dataStore = self.dependencies.own.dataStore
        let siteService = self.dependencies.own.siteService
        let accountService = self.dependencies.own.accountService

        let context = dataStore.mainContext
        let site = siteService.site(for: instance, in: context)

        let personHomeAccount = accountService.account(at: site, in: context)
        let person = accountService
            .lemmyService(for: personHomeAccount)
            .getOrCreate(personId: personId)

        if let personInfo = person.personInfo {
            state = .person(personInfo)
        } else {
            state = .load(person)
        }

        viewModel = PersonOrLoadingViewModel(person.personInfo)

        super.init(nibName: nil, bundle: nil)

        bindViewModel()

        stateChanged()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bindViewModel() {
        viewModel.outputs.personInfoLoaded
            .sink { [weak self] personInfo in
                self?.state = .person(personInfo)
            }
            .store(in: &disposables)

        viewModel.outputs.loadingPersonInfo
            .sink { [weak self] person in
                self?.state = .load(person)
            }
            .store(in: &disposables)

        viewModel.outputs.navigationTitle
            .assign(to: \.title, on: navigationItem)
            .store(in: &disposables)
    }

    private func stateChanged() {
        remove(child: currentViewController)
        currentViewController = nil

        let newViewController: UIViewController
        switch state {
        case let .person(personInfo):
            let contentViewController = PersonViewController(
                personInfo: personInfo,
                dependencies: dependencies.nested
            )
            newViewController = contentViewController

        case let .load(person):
            let loadingViewController = PersonLoadingViewController(
                person: person,
                account: account,
                dependencies: dependencies.nested
            )
            newViewController = loadingViewController

            loadingViewController.didFinishLoading = { [weak self] personInfo in
                self?.viewModel.inputs.didFinishLoadingPersonInfo(personInfo)
            }
        }

        add(child: newViewController)
        addSubviewWithEdgeConstraints(child: newViewController)
    }
}
