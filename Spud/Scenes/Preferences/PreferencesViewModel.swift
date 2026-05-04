//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import Observation
import SpudDataKit
import SwiftUI

@MainActor
@Observable
final class PreferencesViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasPreferencesService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies

    @ObservationIgnored
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)?

    private var preferencesService: PreferencesServiceType? {
        dependencies?.own.preferencesService
    }

    private var accountService: AccountServiceType? {
        dependencies?.own.accountService
    }

    let allPostSortTypes: [Components.Schemas.SortType]
    let allCommentSortTypes: [Components.Schemas.CommentSortType]

    var defaultPostSortType: Components.Schemas.SortType
    var defaultCommentSortType: Components.Schemas.CommentSortType

    var openExternalLink: Preferences.OpenExternalLink
    var openExternalLinkInSafariVCReaderMode: Bool
    var openExternalLinkAsUniversalLinkInApp: Bool

    var storageSize: String
    var storageFileUrl: URL

    /// Async sequence of URLs that the user tapped in the link-testing footer.
    /// The view controller drains this stream to open the URL through
    /// `AppService` honouring the current user preferences.
    @ObservationIgnored
    let externalLinkRequested: AsyncStream<URL>

    @ObservationIgnored
    private let externalLinkRequestedContinuation: AsyncStream<URL>.Continuation

    @ObservationIgnored
    private var preferenceObservationTasks: [Task<Void, Never>] = []

    init(
        defaultPostSortType initialDefaultPostSortType: Components.Schemas.SortType,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        allPostSortTypes = Components.Schemas.SortType.allCases
        allCommentSortTypes = Components.Schemas.CommentSortType.allCases

        defaultPostSortType = initialDefaultPostSortType
        defaultCommentSortType = dependencies.preferencesService.defaultCommentSortType

        openExternalLink = dependencies.preferencesService.openExternalLinks
        openExternalLinkInSafariVCReaderMode =
            dependencies.preferencesService.openExternalLinksInSafariVCReaderMode
        openExternalLinkAsUniversalLinkInApp =
            dependencies.preferencesService.openUniversalLinkInApp

        storageSize = ByteCountFormatter.string(
            fromByteCount: Int64(dependencies.appDatabase.sizeInBytes),
            countStyle: .file
        )
        storageFileUrl = dependencies.appDatabase.storeURL ?? URL(fileURLWithPath: "/")

        let (stream, continuation) = AsyncStream<URL>.makeStream()
        externalLinkRequested = stream
        externalLinkRequestedContinuation = continuation

        let preferencesService = dependencies.preferencesService

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.defaultCommentSortTypePublisher.values {
                self?.defaultCommentSortType = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.openExternalLinksPublisher.values {
                self?.openExternalLink = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.openExternalLinksInSafariVCReaderModePublisher.values {
                self?.openExternalLinkInSafariVCReaderMode = value
            }
        })
    }

    /// Preview-only init with seed values and no service dependencies.
    /// Mutations write back to local state only.
    init(preview: Void = ()) {
        dependencies = nil
        externalLinkRequestedContinuation = AsyncStream<URL>.makeStream().continuation
        externalLinkRequested = AsyncStream { _ in }

        allPostSortTypes = Components.Schemas.SortType.allCases
        allCommentSortTypes = Components.Schemas.CommentSortType.allCases
        defaultPostSortType = .Hot
        defaultCommentSortType = .Hot
        openExternalLink = .safariViewController
        openExternalLinkInSafariVCReaderMode = true
        openExternalLinkAsUniversalLinkInApp = true
        storageSize = "128 MB"
        storageFileUrl = URL(fileURLWithPath: "/tmp")
    }

    deinit {
        externalLinkRequestedContinuation.finish()
        for task in preferenceObservationTasks {
            task.cancel()
        }
    }

    // MARK: Inputs

    func testExternalLink(_ url: URL) {
        externalLinkRequestedContinuation.yield(url)
    }

    func updateDefaultPostSort(_ value: Components.Schemas.SortType) {
        defaultPostSortType = value
        // TODO: persist via /user/save_user_settings once accountService supports it.
    }

    func updateDefaultCommentSort(_ value: Components.Schemas.CommentSortType) {
        defaultCommentSortType = value
        preferencesService?.defaultCommentSortType = value
    }

    func updateOpenExternalLink(_ value: Preferences.OpenExternalLink) {
        openExternalLink = value
        preferencesService?.openExternalLinks = value
    }

    func updateOpenExternalLinkInSafariVCReaderMode(_ value: Bool) {
        openExternalLinkInSafariVCReaderMode = value
        preferencesService?.openExternalLinksInSafariVCReaderMode = value
    }

    func updateOpenExternalLinkAsUniversalLinkInApp(_ value: Bool) {
        openExternalLinkAsUniversalLinkInApp = value
        preferencesService?.openUniversalLinkInApp = value
    }
}
