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

    func testExternalLink(_ url: URL) { }
    func testUniversalLink() { }
    func updateDefaultPostSort(_ sortType: Components.Schemas.SortType) { }
    func updateOpenExternalLink(_ value: Preferences.OpenExternalLink) { }
    func updateOpenExternalLinkInSafariVCReaderMode(_ value: Bool) { }
    func updateDefaultCommentSort(_ commentSortType: Components.Schemas.CommentSortType) { }
    func updateOpenExternalLinkAsUniversalLinkInApp(_ value: Bool) { }

    // MARK: Outputs

    var account: CurrentValueSubject<LemmyAccount, Never> = .init(
        LemmyAccount()
    )

    var externalLinkRequested: AnyPublisher<URL, Never> = .completed

    var allPostSortTypes: [Components.Schemas.SortType] = Components.Schemas.SortType.allCases
    var defaultPostSortType: CurrentValueSubject<Components.Schemas.SortType, Never> = .init(.Hot)
    var defaultPostSortTypeRequested: AnyPublisher<Components.Schemas.SortType, Never> = .completed

    var allCommentSortTypes: [Components.Schemas.CommentSortType] = Components.Schemas.CommentSortType.allCases
    var defaultCommentSortType: CurrentValueSubject<Components.Schemas.CommentSortType, Never> = .init(.Hot)

    var openExternalLink: CurrentValueSubject<Preferences.OpenExternalLink, Never> =
        .init(.safariViewController)
    var openExternalLinkInSafariVCReaderMode: CurrentValueSubject<Bool, Never> = .init(true)
    var openExternalLinkAsUniversalLinkInApp: CurrentValueSubject<Bool, Never> = .init(true)
}
