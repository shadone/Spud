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
}

protocol LoginViewModelOutputs {
    var site: CurrentValueSubject<LemmySite, Never> { get }
    var icon: AnyPublisher<UIImage, Never> { get }
}

protocol LoginViewModelType {
    var inputs: LoginViewModelInputs { get }
    var outputs: LoginViewModelOutputs { get }
}

class LoginViewModel: LoginViewModelType, LoginViewModelInputs, LoginViewModelOutputs {
    // MARK: Private

    private let imageService: ImageServiceType

    var siteInfo: AnyPublisher<LemmySiteInfo, Never> {
        site
            .flatMap { site in
                site.publisher(for: \.siteInfo)
            }
            .ignoreNil()
            .eraseToAnyPublisher()
    }

    // MARK: Functions

    init(
        site: LemmySite,
        imageService: ImageServiceType
    ) {
        self.site = .init(site)
        self.imageService = imageService

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
    }

    // MARK: Type

    var inputs: LoginViewModelInputs { self }
    var outputs: LoginViewModelOutputs { self }

    // MARK: Outputs

    let site: CurrentValueSubject<LemmySite, Never>
    let icon: AnyPublisher<UIImage, Never>

    // MARK: Inputs
}
