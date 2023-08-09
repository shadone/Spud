//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import SpudDataKit
import UIKit

class SiteListSiteViewModel {
    typealias OwnDependencies =
        HasImageService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var imageService: ImageServiceType { dependencies.own.imageService }

    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        instanceHostname
            .combineLatest(titleAttributes)
            .map { description, attributes in
                AttributedString(description, attributes: .init(attributes))
            }
            .eraseToAnyPublisher()
    }

    var descriptionText: AnyPublisher<AttributedString, Never> {
        siteInfo
            .flatMap { siteInfo in
                siteInfo.publisher(for: \.descriptionText)
            }
            .replaceNil(with: "")
            .combineLatest(descriptionAttributes)
            .map { description, attributes in
                AttributedString(description, attributes: .init(attributes))
            }
            .eraseToAnyPublisher()
    }

    var icon: AnyPublisher<ImageLoadingState?, Never> {
        siteInfo
            .flatMap { siteInfo in
                siteInfo.publisher(for: \.iconUrl)
            }
            .flatMap { iconUrl -> AnyPublisher<ImageLoadingState?, Never> in
                guard let iconUrl else {
                    return Just(nil)
                        .eraseToAnyPublisher()
                }
                return self.imageService.fetch(iconUrl)
                    .wrapInOptional()
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private var titleAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2 + textSizeAdjustment, weight: .medium),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var descriptionAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 2 + textSizeAdjustment, weight: .regular),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var siteInfo: AnyPublisher<LemmySiteInfo, Never> {
        site.publisher(for: \.siteInfo)
            .ignoreNil()
            .eraseToAnyPublisher()
    }

    private var instance: AnyPublisher<Instance, Never> {
        site.publisher(for: \.instance)
            .eraseToAnyPublisher()
    }

    private var instanceHostname: AnyPublisher<String, Never> {
        instance
            .flatMap { instance in
                instance.actorIdPublisher
                    .map(\.host)
            }
            .eraseToAnyPublisher()
    }

    private let site: LemmySite

    // MARK: Functions

    init(site: LemmySite, dependencies: Dependencies) {
        self.site = site
        self.dependencies = (own: dependencies, nested: dependencies)
    }
}
