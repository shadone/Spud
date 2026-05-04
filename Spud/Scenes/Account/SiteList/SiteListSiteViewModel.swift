//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import SpudDataKit
import UIKit

@MainActor
class SiteListSiteViewModel {
    typealias OwnDependencies =
        HasImageService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    // MARK: Public

    let row: SiteListRow

    var title: AnyPublisher<AttributedString, Never> {
        Just(row.hostname)
            .map { hostname -> AttributedString in
                AttributedString(hostname, attributes: .init([
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2, weight: .medium),
                    .foregroundColor: UIColor.label,
                ]))
            }
            .eraseToAnyPublisher()
    }

    var descriptionText: AnyPublisher<AttributedString, Never> {
        Just(row.descriptionText ?? "")
            .map { description -> AttributedString in
                AttributedString(description, attributes: .init([
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 2, weight: .regular),
                    .foregroundColor: UIColor.label,
                ]))
            }
            .eraseToAnyPublisher()
    }

    var icon: AnyPublisher<ImageLoadingState?, Never> {
        guard let iconUrl = row.iconUrl else {
            return Just(nil).eraseToAnyPublisher()
        }
        return imageService.fetchPublisher(iconUrl)
            .wrapInOptional()
            .eraseToAnyPublisher()
    }

    // MARK: Functions

    init(row: SiteListRow, dependencies: Dependencies) {
        self.row = row
        self.dependencies = (own: dependencies, nested: dependencies)
    }
}
