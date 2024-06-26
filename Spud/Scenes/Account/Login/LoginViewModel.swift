//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
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
    var site: CurrentValueSubject<LemmySite, Never> { get }
    var icon: AnyPublisher<UIImage, Never> { get }
    var instanceName: AnyPublisher<String, Never> { get }
    var loginButtonEnabled: AnyPublisher<Bool, Never> { get }
    var loggedIn: PassthroughSubject<LemmyAccount, Never> { get }
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

    var accountService: AccountServiceType { dependencies.own.accountService }
    var alertService: AlertServiceType { dependencies.own.alertService }

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    private var siteInfo: AnyPublisher<LemmySiteInfo, Never> {
        site
            .flatMap { site in
                site.publisher(for: \.siteInfo)
            }
            .ignoreNil()
            .eraseToAnyPublisher()
    }

    private let username: CurrentValueSubject<String, Never>
    private let password: CurrentValueSubject<String, Never>

    // MARK: Functions

    init(
        site: LemmySite,
        dependencies: Dependencies
    ) {
        self.site = .init(site)
        self.dependencies = (own: dependencies, nested: dependencies)

        icon = site.publisher(for: \.siteInfo)
            .ignoreNil()
            .flatMap { siteInfo in
                siteInfo.publisher(for: \.iconUrl)
            }
            .flatMap { iconUrl -> AnyPublisher<UIImage, Never> in
                let placeholder = UIImage(systemName: "questionmark")!
                guard let iconUrl else {
                    return Just(placeholder).eraseToAnyPublisher()
                }
                return dependencies.imageService.fetch(iconUrl)
                    .map { state -> UIImage? in
                        switch state {
                        case .loading:
                            return nil
                        case let .ready(image):
                            return image
                        case .failure:
                            return placeholder
                        }
                    }
                    .ignoreNil()
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()

        instanceName = site.publisher(for: \.instance)
            .flatMap(\.actorIdPublisher)
            .map(\.host)
            .eraseToAnyPublisher()

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

    var inputs: LoginViewModelInputs { self }
    var outputs: LoginViewModelOutputs { self }

    // MARK: Outputs

    let site: CurrentValueSubject<LemmySite, Never>
    let icon: AnyPublisher<UIImage, Never>
    let instanceName: AnyPublisher<String, Never>
    let loginButtonEnabled: AnyPublisher<Bool, Never>
    let loggedIn: PassthroughSubject<LemmyAccount, Never>

    // MARK: Inputs

    func usernameChanged(_ username: String) {
        self.username.send(username)
    }

    func passwordChanged(_ password: String) {
        self.password.send(password)
    }

    func login() async {
        do {
            let account = try await accountService.login(
                site: site.value,
                username: username.value,
                password: password.value
            )
            loggedIn.send(account)
        } catch {
            alertService.handle(error, for: .login)
        }
    }
}
