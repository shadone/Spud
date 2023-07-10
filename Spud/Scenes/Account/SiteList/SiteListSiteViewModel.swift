//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class SiteListSiteViewModel {
    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        site.publisher(for: \.normalizedInstanceUrl)
            .map { normalizedInstanceUrl in
                URL(string: normalizedInstanceUrl)?.safeHost ?? ""
            }
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

    var siteInfo: AnyPublisher<LemmySiteInfo, Never> {
        site.publisher(for: \.siteInfo)
            .ignoreNil()
            .eraseToAnyPublisher()
    }

    private let site: LemmySite
    private let imageService: ImageServiceType

    // MARK: Functions

    init(site: LemmySite, imageService: ImageServiceType) {
        self.site = site
        self.imageService = imageService
    }
}
