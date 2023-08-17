//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import SpudDataKit

class PreferencesViewModelForPreview:
    PreferencesViewModelType,
    PreferencesViewModelInputs,
    PreferencesViewModelOutputs
{
    var inputs: PreferencesViewModelInputs { self }
    var outputs: PreferencesViewModelOutputs { self }

    // MARK: Inputs

    func testExternalLink() { }
    func updateDefaultPostSort(_ sortType: SortType) { }
    func updateOpenExternalLink(_ value: Preferences.OpenExternalLink) { }
    func updateOpenExternalLinkInSafariVCReaderMode(_ value: Bool) { }

    // MARK: Outputs

    var account: CurrentValueSubject<LemmyAccount, Never> = .init(
        LemmyAccount()
    )

    var externalLinkForTesting = URL(string: "https://example.com")!
    var externalLinkRequested: AnyPublisher<URL, Never> = .completed

    var allPostSortTypes: [SortType] = SortType.allCases
    var defaultPostSortType: CurrentValueSubject<SortType, Never> = .init(.hot)
    var defaultPostSortTypeRequested: AnyPublisher<SortType, Never> = .completed

    var openExternalLink: CurrentValueSubject<Preferences.OpenExternalLink, Never> =
        .init(.safariViewController)
    var openExternalLinkInSafariVCReaderMode: CurrentValueSubject<Bool, Never> = .init(true)
}
