//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit
import UIKit

@MainActor
@Observable
final class LoginViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasImageService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies

    @ObservationIgnored
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    let row: SiteListRow
    let instanceName: String

    var icon: UIImage
    var username: String = ""
    var password: String = ""
    var loggedIn: Bool = false

    var loginButtonEnabled: Bool {
        !username.isEmpty && !password.isEmpty
    }

    @ObservationIgnored
    private var iconFetchTask: Task<Void, Never>?

    init(
        row: SiteListRow,
        dependencies: Dependencies
    ) {
        self.row = row
        self.dependencies = (own: dependencies, nested: dependencies)
        instanceName = row.hostname

        let placeholder = UIImage(systemName: "questionmark")!
        icon = placeholder

        if let iconUrl = row.iconUrl {
            let stream = dependencies.imageService.fetch(iconUrl)
            iconFetchTask = Task { [weak self] in
                for await state in stream {
                    guard let self else { return }
                    switch state {
                    case .loading:
                        break
                    case let .ready(loaded):
                        icon = loaded
                    case .failure:
                        icon = placeholder
                    }
                }
            }
        }
    }

    deinit {
        iconFetchTask?.cancel()
    }

    func login() async {
        do {
            try await accountService.login(
                atInstance: row.instance,
                username: username,
                password: password
            )
            loggedIn = true
        } catch {
            alertService.handle(error, for: .login)
        }
    }
}
