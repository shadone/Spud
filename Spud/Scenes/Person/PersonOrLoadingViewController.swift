//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import UIKit

class PersonOrLoadingViewController: UIViewController {
    typealias Dependencies =
        PersonViewController.Dependencies &
        PersonLoadingViewController.Dependencies
    private let dependencies: Dependencies

    // MARK: - Public

    private(set) var contentViewController: PersonViewController?

    // MARK: - Private

    private let viewModel: PersonOrLoadingViewModelType

    private enum State {
        case personInfo(LemmyPersonInfo)
        case load(LemmyPerson)
    }

    private var state: State {
        didSet {
            stateChanged()
        }
    }

    private var loadingViewController: PersonLoadingViewController?
    private var disposables = Set<AnyCancellable>()

    // MARK: - Functions

    init(
        person: LemmyPerson,
        account: LemmyAccount,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies

        state = .load(person)
        viewModel = PersonOrLoadingViewModel(person: person, account: account)

        super.init(nibName: nil, bundle: nil)

        bindViewModel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bindViewModel() {
        viewModel.outputs.loadedPersonInfo
            .sink { [weak self] personInfo in
                self?.state = .personInfo(personInfo)
            }
            .store(in: &disposables)

        viewModel.outputs.loadingPersonInfo
            .sink { [weak self] person in
                self?.state = .load(person)
            }
            .store(in: &disposables)
    }

    private func stateChanged() {
        switch state {
        case let .personInfo(personInfo):
            assert(contentViewController == nil, "content should only be loaded once")
            contentViewController = PersonViewController(
                personInfo: personInfo,
                dependencies: dependencies
            )

            remove(child: loadingViewController)
            add(child: contentViewController)
            addSubviewWithEdgeConstraints(child: contentViewController)

            loadingViewController = nil

        case let .load(person):
            let loadingViewController = PersonLoadingViewController(
                person: person,
                account: viewModel.outputs.account,
                dependencies: dependencies
            )
            self.loadingViewController = loadingViewController

            viewModel.inputs.startLoadingPersonInfo()
            loadingViewController.didFinishLoading = { [weak self] personInfo in
                self?.viewModel.inputs.didFinishLoadingPersonInfo(personInfo)
            }

            remove(child: contentViewController)
            add(child: loadingViewController)
            addSubviewWithEdgeConstraints(child: loadingViewController)

            contentViewController = nil
        }
    }
}
