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
    func updateDefaultPostSort(_ sortType: SortType) { }
    func updateOpenExternalLink(_ value: Preferences.OpenExternalLink) { }
    func updateOpenExternalLinkInSafariVCReaderMode(_ value: Bool) { }
    func updateDefaultCommentSort(_ commentSortType: LemmyKit.CommentSortType) { }
    func updateOpenExternalLinkAsUniversalLinkInApp(_ value: Bool) { }

    // MARK: Outputs

    var account: CurrentValueSubject<LemmyAccount, Never> = .init(
        LemmyAccount()
    )

    var externalLinkRequested: AnyPublisher<URL, Never> = .completed

    var allPostSortTypes: [SortType] = SortType.allCases
    var defaultPostSortType: CurrentValueSubject<SortType, Never> = .init(.hot)
    var defaultPostSortTypeRequested: AnyPublisher<SortType, Never> = .completed

    var allCommentSortTypes: [CommentSortType] = CommentSortType.allCases
    var defaultCommentSortType: CurrentValueSubject<CommentSortType, Never> = .init(.hot)

    var openExternalLink: CurrentValueSubject<Preferences.OpenExternalLink, Never> =
        .init(.safariViewController)
    var openExternalLinkInSafariVCReaderMode: CurrentValueSubject<Bool, Never> = .init(true)
    var openExternalLinkAsUniversalLinkInApp: CurrentValueSubject<Bool, Never> = .init(true)

    var storageSize: CurrentValueSubject<String, Never> = .init("128 MB")
    var storageFileUrl: CurrentValueSubject<URL, Never> = .init(URL(string: "file:///tmp")!)
}
