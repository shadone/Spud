//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

protocol PersonOrLoadingViewModelInputs {
    func startLoadingPersonInfo(person: LemmyPerson)
    func didFinishLoadingPersonInfo(_ personInfo: LemmyPersonInfo)
    func displayPersonInfo(_ personInfo: LemmyPersonInfo)
}

protocol PersonOrLoadingViewModelOutputs {
    var currentPersonInfo: AnyPublisher<LemmyPersonInfo?, Never> { get }
    var loadPersonInfo: AnyPublisher<LemmyPerson, Never> { get }
    var personInfoLoaded: AnyPublisher<LemmyPersonInfo, Never> { get }
}

protocol PersonOrLoadingViewModelType {
    var inputs: PersonOrLoadingViewModelInputs { get }
    var outputs: PersonOrLoadingViewModelOutputs { get }
}

class PersonOrLoadingViewModel
    : PersonOrLoadingViewModelType,
      PersonOrLoadingViewModelInputs,
      PersonOrLoadingViewModelOutputs
{
    private let currentlyDisplayedPersonInfo: CurrentValueSubject<LemmyPersonInfo?, Never>
    private var disposables = Set<AnyCancellable>()

    init() {
        currentlyDisplayedPersonInfo = CurrentValueSubject<LemmyPersonInfo?, Never>(nil)

        personInfoLoaded = currentlyDisplayedPersonInfo
            .ignoreNil()
            .eraseToAnyPublisher()

        currentPersonInfo = currentlyDisplayedPersonInfo
            .eraseToAnyPublisher()

        loadPersonInfo = startLoadingPersonInfoSubject
            .ignoreNil()
            .eraseToAnyPublisher()

        didFinishLoadingPersonInfoSubject
            .sink { [weak self] personInfo in
                self?.currentlyDisplayedPersonInfo.send(personInfo)
            }
            .store(in: &disposables)

        displayPersonInfoSubject
            .sink { [weak self] personInfo in
                self?.currentlyDisplayedPersonInfo.send(personInfo)
            }
            .store(in: &disposables)
    }

    // MARK: Type

    var inputs: PersonOrLoadingViewModelInputs { self }
    var outputs: PersonOrLoadingViewModelOutputs { self }

    // MARK: Outputs

    let currentPersonInfo: AnyPublisher<LemmyPersonInfo?, Never>
    let loadPersonInfo: AnyPublisher<LemmyPerson, Never>
    let personInfoLoaded: AnyPublisher<LemmyPersonInfo, Never>

    // MARK: Inputs

    private let startLoadingPersonInfoSubject = PassthroughSubject<LemmyPerson?, Never>()
    func startLoadingPersonInfo(person: LemmyPerson) {
        startLoadingPersonInfoSubject.send(person)
    }

    private let didFinishLoadingPersonInfoSubject = PassthroughSubject<LemmyPersonInfo?, Never>()
    func didFinishLoadingPersonInfo(_ personInfo: LemmyPersonInfo) {
        didFinishLoadingPersonInfoSubject.send(personInfo)
    }

    private let displayPersonInfoSubject = PassthroughSubject<LemmyPersonInfo?, Never>()
    func displayPersonInfo(_ personInfo: LemmyPersonInfo) {
        displayPersonInfoSubject.send(personInfo)
    }
}
