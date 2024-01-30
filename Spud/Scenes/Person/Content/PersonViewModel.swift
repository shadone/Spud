//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import SpudDataKit
import UIKit

protocol PersonViewModelInputs { }

protocol PersonViewModelOutputs {
    /// Username (aka nickname aka short users' name). e.g. "helloworld"
    var name: AnyPublisher<String, Never> { get }

    /// The name of the instance the user belongs to.
    var homeInstance: AnyPublisher<String, Never> { get }

    /// A display name for the user. e.g. "Hello World!"
    var displayName: AnyPublisher<String?, Never> { get }

    var numberOfPosts: AnyPublisher<String, Never> { get }

    var numberOfComments: AnyPublisher<String, Never> { get }

    var accountAge: AnyPublisher<String, Never> { get }
}

protocol PersonViewModelType: ObservableObject {
    var inputs: PersonViewModelInputs { get }
    var outputs: PersonViewModelOutputs { get }
}

class PersonViewModel:
    PersonViewModelType,
    PersonViewModelInputs,
    PersonViewModelOutputs
{
    typealias OwnDependencies =
        HasVoid
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: Private

    private let personInfo: LemmyPersonInfo
    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        personInfo: LemmyPersonInfo,
        dependencies: Dependencies
    ) {
        self.personInfo = personInfo
        self.dependencies = (own: dependencies, nested: dependencies)

        name = personInfo.publisher(for: \.name)
            .eraseToAnyPublisher()

        homeInstance = personInfo.instanceActorIdPublisher
            .map { "@\($0.host)" }
            .eraseToAnyPublisher()

        displayName = personInfo.publisher(for: \.displayName)
            .eraseToAnyPublisher()

        numberOfPosts = personInfo.publisher(for: \.numberOfPosts)
            .map { CommentsFormatter.string(from: $0) }
            .eraseToAnyPublisher()

        numberOfComments = personInfo.publisher(for: \.numberOfComments)
            .map { CommentsFormatter.string(from: $0) }
            .eraseToAnyPublisher()

        accountAge = personInfo.publisher(for: \.personCreatedDate)
            .map {
                PersonFormatter.string(personCreatedDate: $0)
            }
            .eraseToAnyPublisher()
    }

    // MARK: Type

    var inputs: PersonViewModelInputs { self }
    var outputs: PersonViewModelOutputs { self }

    // MARK: Outputs

    let name: AnyPublisher<String, Never>
    let homeInstance: AnyPublisher<String, Never>
    let displayName: AnyPublisher<String?, Never>
    let numberOfPosts: AnyPublisher<String, Never>
    let numberOfComments: AnyPublisher<String, Never>
    let accountAge: AnyPublisher<String, Never>

    // MARK: Inputs
}
