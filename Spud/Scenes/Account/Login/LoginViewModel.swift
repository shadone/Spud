//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import SpudDataKit
import UIKit

@MainActor
protocol LoginViewModelInputs {
    func usernameChanged(_ username: String)
    func passwordChanged(_ password: String)
    func login() async
}

@MainActor
protocol LoginViewModelOutputs {
    var row: SiteListRow { get }
    var icon: AnyPublisher<UIImage, Never> { get }
    var instanceName: AnyPublisher<String, Never> { get }
    var loginButtonEnabled: AnyPublisher<Bool, Never> { get }
    var loggedIn: PassthroughSubject<Void, Never> { get }
}

@MainActor
protocol LoginViewModelType {
    var inputs: LoginViewModelInputs { get }
    var outputs: LoginViewModelOutputs { get }
}

@MainActor
class LoginViewModel: LoginViewModelType, LoginViewModelInputs, LoginViewModelOutputs {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasImageService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    // MARK: Private

    private let username: CurrentValueSubject<String, Never>
    private let password: CurrentValueSubject<String, Never>

    // MARK: Functions

    init(
        row: SiteListRow,
        dependencies: Dependencies
    ) {
        self.row = row
        self.dependencies = (own: dependencies, nested: dependencies)

        let placeholder = UIImage(systemName: "questionmark")!
        if let iconUrl = row.iconUrl {
            let stream = dependencies.imageService.fetch(iconUrl)
            let subject = PassthroughSubject<UIImage, Never>()
            let task = Task { [subject] in
                for await state in stream {
                    let image: UIImage?
                    switch state {
                    case .loading:
                        image = nil
                    case let .ready(loaded):
                        image = loaded
                    case .failure:
                        image = placeholder
                    }
                    if let image {
                        subject.send(image)
                    }
                }
                subject.send(completion: .finished)
            }
            icon = subject
                .handleEvents(receiveCancel: { task.cancel() })
                .eraseToAnyPublisher()
        } else {
            icon = Just(placeholder).eraseToAnyPublisher()
        }

        instanceName = Just(row.hostname).eraseToAnyPublisher()

        username = .init("")
        password = .init("")
        loginButtonEnabled = username.combineLatest(password)
            .map { username, password in
                !username.isEmpty && !password.isEmpty
            }
            .eraseToAnyPublisher()
        loggedIn = .init()
    }

    // MARK: Type

    var inputs: LoginViewModelInputs {
        self
    }

    var outputs: LoginViewModelOutputs {
        self
    }

    // MARK: Outputs

    let row: SiteListRow
    let icon: AnyPublisher<UIImage, Never>
    let instanceName: AnyPublisher<String, Never>
    let loginButtonEnabled: AnyPublisher<Bool, Never>
    let loggedIn: PassthroughSubject<Void, Never>

    // MARK: Inputs

    func usernameChanged(_ username: String) {
        self.username.send(username)
    }

    func passwordChanged(_ password: String) {
        self.password.send(password)
    }

    func login() async {
        do {
            try await accountService.login(
                atInstance: row.instance,
                username: username.value,
                password: password.value
            )
            loggedIn.send(())
        } catch {
            alertService.handle(error, for: .login)
        }
    }
}
