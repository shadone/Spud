//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

protocol PersonOrLoadingViewModelInputs {
    func startLoadingPersonInfo()
    func didFinishLoadingPersonInfo(_ personInfo: LemmyPersonInfo)
}

protocol PersonOrLoadingViewModelOutputs {
    var account: LemmyAccount { get }
    var loadingPersonInfo: AnyPublisher<LemmyPerson, Never> { get }
    var loadedPersonInfo: AnyPublisher<LemmyPersonInfo, Never> { get }
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
    private let person: LemmyPerson
    private let currentlyDisplayedPersonInfo: CurrentValueSubject<LemmyPersonInfo?, Never>
    private var disposables = Set<AnyCancellable>()

    init(person: LemmyPerson, account: LemmyAccount) {
        self.person = person
        self.account = account

        let personInfo: LemmyPersonInfo? = nil // person.personInfo
        currentlyDisplayedPersonInfo = CurrentValueSubject<LemmyPersonInfo?, Never>(personInfo)

        let initialLoadingPersonInfo: AnyPublisher<LemmyPerson, Never>
        if personInfo == nil {
            initialLoadingPersonInfo = .just(person)
        } else {
            initialLoadingPersonInfo = .empty(completeImmediately: true)
        }
        loadingPersonInfo = initialLoadingPersonInfo
            .append(startLoadingPersonInfoSubject)
            .eraseToAnyPublisher()

        loadedPersonInfo = currentlyDisplayedPersonInfo
            .ignoreNil()
            .eraseToAnyPublisher()

        didFinishLoadingPersonInfoSubject
            .sink { [weak self] personInfo in
                self?.currentlyDisplayedPersonInfo.send(personInfo)
            }
            .store(in: &disposables)
    }

    // MARK: Type

    var inputs: PersonOrLoadingViewModelInputs { self }
    var outputs: PersonOrLoadingViewModelOutputs { self }

    // MARK: Outputs

    let account: LemmyAccount
    let loadingPersonInfo: AnyPublisher<LemmyPerson, Never>
    let loadedPersonInfo: AnyPublisher<LemmyPersonInfo, Never>

    // MARK: Inputs

    private let startLoadingPersonInfoSubject = PassthroughSubject<LemmyPerson, Never>()
    func startLoadingPersonInfo() {
        startLoadingPersonInfoSubject.send(person)
    }

    private let didFinishLoadingPersonInfoSubject = PassthroughSubject<LemmyPersonInfo?, Never>()
    func didFinishLoadingPersonInfo(_ personInfo: LemmyPersonInfo) {
        didFinishLoadingPersonInfoSubject.send(personInfo)
    }
}
