//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUIKit
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

    var appService: AppServiceType {
        dependencies.own.appService
    }

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private let viewModel: PreferencesViewModel
    private var externalLinkTask: Task<Void, Never>?
    private var draftsOutboxTask: Task<Void, Never>?

    init(
        defaultPostSortType: Lemmy.SortType,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PreferencesViewModel(
            defaultPostSortType: defaultPostSortType,
            accountKeychainId: accountKeychainId,
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

    deinit {
        externalLinkTask?.cancel()
        draftsOutboxTask?.cancel()
    }

    private func setup() {
        view.backgroundColor = Theme.background

        tabBarItem.title = "Preferences"
        tabBarItem.image = UIImage(systemName: "gear")!

        navigationItem.title = "Preferences"

        let contentVC = UIHostingController(rootView: PreferencesView(viewModel: viewModel))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)
    }

    private func bindViewModel() {
        externalLinkTask = Task { @MainActor [weak self, viewModel] in
            for await url in viewModel.externalLinkRequested {
                guard let self else { return }
                await appService.open(url: url, on: self)
            }
        }

        draftsOutboxTask = Task { @MainActor [weak self, viewModel] in
            for await _ in viewModel.draftsOutboxRequested {
                guard let self else { return }
                let vc = OutboundContentListViewController(
                    accountKeychainId: viewModel.accountKeychainId,
                    dependencies: dependencies.nested
                )
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
}
