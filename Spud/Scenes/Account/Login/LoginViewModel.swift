//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import LemmyKit
import UIKit

protocol LoginViewModelInputs {
    func usernameChanged(_ username: String)
    func passwordChanged(_ password: String)
    func login()
}

protocol LoginViewModelOutputs {
    var site: CurrentValueSubject<LemmySite, Never> { get }
    var icon: AnyPublisher<UIImage, Never> { get }
    var instanceName: AnyPublisher<String, Never> { get }
    var loginButtonEnabled: AnyPublisher<Bool, Never> { get }
    var loggedIn: PassthroughSubject<LemmyAccount, Never> { get }
}

protocol LoginViewModelType {
    var inputs: LoginViewModelInputs { get }
    var outputs: LoginViewModelOutputs { get }
}

class LoginViewModel: LoginViewModelType, LoginViewModelInputs, LoginViewModelOutputs {
    typealias Dependencies =
        HasImageService &
        HasAccountService &
        HasAlertService
    private let dependencies: Dependencies

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
        self.dependencies = dependencies

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
                return dependencies.imageService.get(iconUrl)
                    .replaceError(with: placeholder)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()

        instanceName = site.instanceHostnamePublisher

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

    func login() {
        dependencies.accountService.login(
            site: site.value,
            username: username.value,
            password: password.value
        )
        .sink(
            receiveCompletion: dependencies.alertService.errorHandler(for: .login),
            receiveValue: { [weak self] account in
                self?.loggedIn.send(account)
            }
        )
        .store(in: &disposables)
    }
}
