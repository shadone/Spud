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
    // MARK: Private

    private let imageService: ImageServiceType
    private let accountService: AccountServiceType
    private var disposables = Set<AnyCancellable>()

    var siteInfo: AnyPublisher<LemmySiteInfo, Never> {
        site
            .flatMap { site in
                site.publisher(for: \.siteInfo)
            }
            .ignoreNil()
            .eraseToAnyPublisher()
    }

    let username: CurrentValueSubject<String, Never>
    let password: CurrentValueSubject<String, Never>

    // MARK: Functions

    init(
        site: LemmySite,
        imageService: ImageServiceType,
        accountService: AccountServiceType
    ) {
        self.site = .init(site)
        self.imageService = imageService
        self.accountService = accountService

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
                return imageService.get(iconUrl)
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
        accountService.login(
            site: site.value,
            username: username.value,
            password: password.value
        )
        .sink { _ in
        } receiveValue: { [weak self] account in
            self?.loggedIn.send(account)
        }
        .store(in: &disposables)
    }
}
