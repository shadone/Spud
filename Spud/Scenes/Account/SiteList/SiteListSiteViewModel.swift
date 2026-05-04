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
final class SiteListSiteViewModel {
    typealias OwnDependencies =
        HasImageService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies

    @ObservationIgnored
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    let row: SiteListRow
    let title: AttributedString
    let descriptionText: AttributedString

    var iconState: ImageLoadingState?

    @ObservationIgnored
    private var iconFetchTask: Task<Void, Never>?

    init(row: SiteListRow, dependencies: Dependencies) {
        self.row = row
        self.dependencies = (own: dependencies, nested: dependencies)

        title = AttributedString(row.hostname, attributes: .init([
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2, weight: .medium),
            .foregroundColor: UIColor.label,
        ]))
        descriptionText = AttributedString(row.descriptionText ?? "", attributes: .init([
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 2, weight: .regular),
            .foregroundColor: UIColor.label,
        ]))

        if let iconUrl = row.iconUrl {
            let stream = imageService.fetch(iconUrl)
            iconFetchTask = Task { [weak self] in
                for await state in stream {
                    guard let self else { return }
                    iconState = state
                }
            }
        } else {
            iconState = nil
        }
    }

    deinit {
        iconFetchTask?.cancel()
    }
}
