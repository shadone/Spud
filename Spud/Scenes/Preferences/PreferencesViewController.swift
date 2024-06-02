//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI
import UIKit

class PreferencesViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppService &
        HasPreferencesService
    typealias NestedDependencies =
        PreferencesViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var appService: AppServiceType { dependencies.own.appService }
    var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: - Private

    private let viewModel: PreferencesViewModel

    private var disposables = Set<AnyCancellable>()

    // MARK: - Functions

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PreferencesViewModel(
            account: account,
            dependencies: self.dependencies.nested
        )
        super.init(nibName: nil, bundle: nil)

        setup()
        bindViewModel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        tabBarItem.title = "Preferences"
        tabBarItem.image = UIImage(systemName: "gear")!

        navigationItem.title = "Preferences"

        let contentVC = UIHostingController(rootView: PreferencesView(
            viewModel: self.viewModel
        ))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)
    }

    private func bindViewModel() {
        viewModel.outputs.externalLinkRequested
            .sink { [weak self] url in
                guard let self else { return }
                Task {
                    await self.appService.open(url: url, on: self)
                }
            }
            .store(in: &disposables)

        viewModel.outputs.defaultPostSortTypeRequested
            .sink { [weak self] sortType in
                self?.updateDefaultPostSortType(sortType)
            }
            .store(in: &disposables)
    }

    private func updateDefaultPostSortType(_ sortType: Components.Schemas.SortType) {
        // TODO: update user preferences using /user/save_user_settings api call
        // accountService.lemmyService(for: viewModel.outputs.account.value)
        //     .updateAccountInfo()
    }
}
