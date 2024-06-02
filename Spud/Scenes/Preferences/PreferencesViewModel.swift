//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI

protocol PreferencesViewModelInputs {
    /// Opens external link as per current user configuration.
    func testExternalLink(_ url: URL)

    func updateDefaultPostSort(_ sortType: SortType)

    func updateDefaultCommentSort(_ commentSortType: CommentSortType)

    func updateOpenExternalLink(_ value: Preferences.OpenExternalLink)

    func updateOpenExternalLinkInSafariVCReaderMode(_ value: Bool)

    func updateOpenExternalLinkAsUniversalLinkInApp(_ value: Bool)
}

protocol PreferencesViewModelOutputs {
    var account: CurrentValueSubject<LemmyAccount, Never> { get }

    // MARK: Testing opening external link

    var externalLinkRequested: AnyPublisher<URL, Never> { get }

    // MARK: Default Post Sort Type

    /// Returns all Post sort types that user can choose from.
    var allPostSortTypes: [SortType] { get }

    /// The default sort type for post listing that the user has chosen.
    var defaultPostSortType: CurrentValueSubject<SortType, Never> { get }

    /// The user chose a different sort type.
    var defaultPostSortTypeRequested: AnyPublisher<SortType, Never> { get }

    // MARK: Default Comment Sort Type

    /// Returns all Comment sort types that user can choose from.
    var allCommentSortTypes: [CommentSortType] { get }

    /// The default sort type for comments that the user has chosen.
    var defaultCommentSortType: CurrentValueSubject<CommentSortType, Never> { get }

    // MARK: Open External Link

    var openExternalLink: CurrentValueSubject<Preferences.OpenExternalLink, Never> { get }
    var openExternalLinkInSafariVCReaderMode: CurrentValueSubject<Bool, Never> { get }
    var openExternalLinkAsUniversalLinkInApp: CurrentValueSubject<Bool, Never> { get }

    // MARK: Storage info

    var storageSize: CurrentValueSubject<String, Never> { get }
    var storageFileUrl: CurrentValueSubject<URL, Never> { get }
}

protocol PreferencesViewModelType: ObservableObject {
    var inputs: PreferencesViewModelInputs { get }
    var outputs: PreferencesViewModelOutputs { get }
}

class PreferencesViewModel:
    PreferencesViewModelType,
    PreferencesViewModelInputs,
    PreferencesViewModelOutputs
{
    typealias OwnDependencies =
        HasAccountService &
        HasDataStore &
        HasPreferencesService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var preferencesService: PreferencesServiceType { dependencies.own.preferencesService }
    var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        account: LemmyAccount,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        self.account = CurrentValueSubject<LemmyAccount, Never>(account)

        externalLinkRequested = testExternalLinkSubject.eraseToAnyPublisher()

        // TODO: omit sort types that User's instance cannot handle
        // (e.g. old Lemmy instance not supporting topSixHour sort)
        allPostSortTypes = SortType.allCases

        defaultPostSortType = .init(account.accountInfo?.defaultSortType ?? .hot)
        defaultPostSortTypeRequested = updateDefaultPostSortSubject
            .eraseToAnyPublisher()

        let preferencesService = dependencies.preferencesService

        // TODO: omit sort types that User's instance cannot handle
        // (e.g. old Lemmy instance not supporting topSixHour sort)
        allCommentSortTypes = CommentSortType.allCases

        defaultCommentSortType = .init(preferencesService.defaultCommentSortType)

        openExternalLink = .init(preferencesService.openExternalLinks)

        openExternalLinkInSafariVCReaderMode = .init(preferencesService.openExternalLinksInSafariVCReaderMode)

        openExternalLinkAsUniversalLinkInApp = .init(preferencesService.openUniversalLinkInApp)

        storageSize = .init(ByteCountFormatter.string(
            fromByteCount: Int64(dependencies.dataStore.sizeInBytes),
            countStyle: .file
        ))

        storageFileUrl = .init(dependencies.dataStore.storeUrl)

        preferencesService.defaultCommentSortTypePublisher
            .sink { [weak self] value in
                self?.defaultCommentSortType.send(value)
            }
            .store(in: &disposables)

        preferencesService.openExternalLinksPublisher
            .assign(to: \.value, on: openExternalLink)
            .store(in: &disposables)

        preferencesService.openExternalLinksInSafariVCReaderModePublisher
            .sink { [weak self] value in
                self?.openExternalLinkInSafariVCReaderMode.send(value)
            }
            .store(in: &disposables)
    }

    // MARK: Type

    var inputs: PreferencesViewModelInputs { self }
    var outputs: PreferencesViewModelOutputs { self }

    // MARK: Outputs

    let account: CurrentValueSubject<LemmyAccount, Never>

    let externalLinkRequested: AnyPublisher<URL, Never>

    let allPostSortTypes: [SortType]
    let defaultPostSortType: CurrentValueSubject<SortType, Never>
    let defaultPostSortTypeRequested: AnyPublisher<SortType, Never>

    let allCommentSortTypes: [CommentSortType]
    let defaultCommentSortType: CurrentValueSubject<CommentSortType, Never>

    let openExternalLink: CurrentValueSubject<Preferences.OpenExternalLink, Never>
    let openExternalLinkInSafariVCReaderMode: CurrentValueSubject<Bool, Never>
    let openExternalLinkAsUniversalLinkInApp: CurrentValueSubject<Bool, Never>

    let storageSize: CurrentValueSubject<String, Never>
    let storageFileUrl: CurrentValueSubject<URL, Never>

    // MARK: Inputs

    let testExternalLinkSubject: PassthroughSubject<URL, Never> = .init()
    func testExternalLink(_ url: URL) {
        testExternalLinkSubject.send(url)
    }

    let updateDefaultPostSortSubject: PassthroughSubject<SortType, Never> = .init()
    func updateDefaultPostSort(_ value: SortType) {
        // Send the new value before the request to update it completes to update the UI early.
        defaultPostSortType.send(value)

        updateDefaultPostSortSubject.send(value)
        objectWillChange.send()
    }

    let updateDefaultCommentSortSubject: PassthroughSubject<CommentSortType, Never> = .init()
    func updateDefaultCommentSort(_ value: CommentSortType) {
        preferencesService.defaultCommentSortType = value
        objectWillChange.send()
    }

    func updateOpenExternalLink(_ value: Preferences.OpenExternalLink) {
        preferencesService.openExternalLinks = value
        objectWillChange.send()
    }

    func updateOpenExternalLinkInSafariVCReaderMode(_ value: Bool) {
        preferencesService.openExternalLinksInSafariVCReaderMode = value
        objectWillChange.send()
    }

    func updateOpenExternalLinkAsUniversalLinkInApp(_ value: Bool) {
        preferencesService.openUniversalLinkInApp = value
        objectWillChange.send()
    }
}
