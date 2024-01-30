//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import SpudDataKit
import UIKit

protocol PersonOrLoadingViewModelInputs {
    func startLoadingPersonInfo(_ person: LemmyPerson)
    func didFinishLoadingPersonInfo(_ personInfo: LemmyPersonInfo)
}

protocol PersonOrLoadingViewModelOutputs {
    var currentPersonInfo: AnyPublisher<LemmyPersonInfo?, Never> { get }
    var loadingPersonInfo: AnyPublisher<LemmyPerson, Never> { get }
    var personInfoLoaded: AnyPublisher<LemmyPersonInfo, Never> { get }
    var navigationTitle: AnyPublisher<String?, Never> { get }
}

protocol PersonOrLoadingViewModelType {
    var inputs: PersonOrLoadingViewModelInputs { get }
    var outputs: PersonOrLoadingViewModelOutputs { get }
}

class PersonOrLoadingViewModel:
    PersonOrLoadingViewModelType,
    PersonOrLoadingViewModelInputs,
    PersonOrLoadingViewModelOutputs
{
    private let currentlyDisplayedPersonInfo: CurrentValueSubject<LemmyPersonInfo?, Never>
    private var disposables = Set<AnyCancellable>()

    init(_ initialPersonInfo: LemmyPersonInfo?) {
        currentlyDisplayedPersonInfo = .init(initialPersonInfo)

        personInfoLoaded = didFinishLoadingPersonInfoSubject
            .ignoreNil()
            .eraseToAnyPublisher()

        currentPersonInfo = currentlyDisplayedPersonInfo
            .eraseToAnyPublisher()

        loadingPersonInfo = startLoadingPersonInfoSubject
            .eraseToAnyPublisher()

        navigationTitle = personInfoLoaded
            .flatMap { personInfo in
                personInfo.publisher(for: \.name)
                    .combineLatest(personInfo.instanceActorIdPublisher)
                    .map { name, instance in
                        // TODO: shall we omit hostname for local users?
                        "@\(name)@\(instance.host)"
                    }
            }
            .wrapInOptional()
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

    let currentPersonInfo: AnyPublisher<LemmyPersonInfo?, Never>
    let loadingPersonInfo: AnyPublisher<LemmyPerson, Never>
    let personInfoLoaded: AnyPublisher<LemmyPersonInfo, Never>
    let navigationTitle: AnyPublisher<String?, Never>

    // MARK: Inputs

    private let startLoadingPersonInfoSubject = PassthroughSubject<LemmyPerson, Never>()
    func startLoadingPersonInfo(_ person: LemmyPerson) {
        startLoadingPersonInfoSubject.send(person)
    }

    private let didFinishLoadingPersonInfoSubject = PassthroughSubject<LemmyPersonInfo?, Never>()
    func didFinishLoadingPersonInfo(_ personInfo: LemmyPersonInfo) {
        didFinishLoadingPersonInfoSubject.send(personInfo)
    }
}
