//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SwiftUI
import UIKit

class PersonViewController: UIViewController {
    typealias OwnDependencies =
        HasAppDatabase
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: - Private

    private let viewModel: PersonViewModel

    // MARK: - Functions

    init(personRowId: Int64, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PersonViewModel(
            personRowId: personRowId,
            appDatabase: dependencies.appDatabase
        )

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        let contentVC = UIHostingController(rootView: PersonView(viewModel: self.viewModel))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)
    }
}
