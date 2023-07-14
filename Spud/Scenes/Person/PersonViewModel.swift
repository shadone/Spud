//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import CoreData
import Combine

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
    typealias Dependencies =
        PersonHeaderViewModel.Dependencies
    private let dependencies: Dependencies

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        personInfo: LemmyPersonInfo,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        self.personInfo = personInfo

        headerViewModel = PersonHeaderViewModel(
            personInfo: personInfo,
            dependencies: dependencies
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
