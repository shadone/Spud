//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import CoreData
import Combine
import SpudDataKit

protocol PersonViewModelInputs {
}

protocol PersonViewModelOutputs {
    var personInfo: LemmyPersonInfo { get }
    var headerViewModel: PersonHeaderViewModel { get }
}

protocol PersonViewModelType {
    var inputs: PersonViewModelInputs { get }
    var outputs: PersonViewModelOutputs { get }
}

class PersonViewModel: PersonViewModelType, PersonViewModelInputs, PersonViewModelOutputs {
    typealias OwnDependencies =
        PersonHeaderViewModel.Dependencies
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        personInfo: LemmyPersonInfo,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.personInfo = personInfo

        headerViewModel = PersonHeaderViewModel(
            personInfo: personInfo,
            dependencies: self.dependencies.nested
        )
    }

    // MARK: Type

    var inputs: PersonViewModelInputs { self }
    var outputs: PersonViewModelOutputs { self }

    // MARK: Outputs

    let personInfo: LemmyPersonInfo
    let headerViewModel: PersonHeaderViewModel

    // MARK: Inputs
}
