//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI
import UIKit

class PersonViewController: UIViewController {
    typealias OwnDependencies =
        HasVoid
    typealias NestedDependencies =
        PersonViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: - UI Properties

    // MARK: - Private

    private var viewModel: PersonViewModel

    // MARK: - Functions

    init(personInfo: LemmyPersonInfo, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PersonViewModel(
            personInfo: personInfo,
            dependencies: self.dependencies.nested
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

        let contentVC = UIHostingController(rootView: PersonView(
            viewModel: self.viewModel
        ))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)
    }
}
