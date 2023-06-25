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
                guard let url = URL(string: normalizedInstanceUrl) else {
                    return normalizedInstanceUrl
                }
                let host: String?
                if #available(iOS 16.0, *) {
                    host = url.host(percentEncoded: false)
                } else {
                    host = url.host
                }
                return host ?? normalizedInstanceUrl
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

    enum IconType {
        /// Site icon.
        case image(UIImage)
        /// Site has no provided icon
        case none
        /// Image failed to load, we display a broken image icon.
        case imageFailure
    }

    var icon: AnyPublisher<IconType, Never> {
        siteInfo
            .flatMap { siteInfo in
                siteInfo.publisher(for: \.iconUrl)
            }
            .flatMap { iconUrl -> AnyPublisher<IconType, Never> in
                guard let iconUrl else {
                    return Just(.none)
                        .eraseToAnyPublisher()
                }
                return self.imageService.get(iconUrl)
                    .map { .image($0) }
                    .replaceError(with: .imageFailure)
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
