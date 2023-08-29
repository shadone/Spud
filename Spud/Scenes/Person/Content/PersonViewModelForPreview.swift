//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

class PersonViewModelForPreview:
    PersonViewModelType,
    PersonViewModelInputs,
    PersonViewModelOutputs
{
    var inputs: PersonViewModelInputs { self }

    var outputs: PersonViewModelOutputs { self }

    // MARK: Inputs

    // MARK: Outputs

    var name: AnyPublisher<String, Never> = .just("helloworld")

    var homeInstance: AnyPublisher<String, Never> = .just("@example.com")

    var displayName: AnyPublisher<String?, Never> = .just("Hello World")

    var postKarma: AnyPublisher<String, Never> = .just("774")

    var numberOfPosts: AnyPublisher<String, Never> = .just("123")

    var commentKarma: AnyPublisher<String, Never> = .just("1.7K")

    var numberOfComments: AnyPublisher<String, Never> = .just("1234")

    var accountAge: AnyPublisher<String, Never> = .just("14y 1mo")
}
