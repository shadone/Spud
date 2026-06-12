//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// View model for the Person profile screen. The header fields are driven by
/// `appDatabase.observePersonProfile` (persisted), while the posts/comments
/// lists are transient - fetched per tab via `LemmyService.fetchPersonContent`
/// and held in memory, mirroring how Search returns its results.
@MainActor
@Observable
final class PersonViewModel {
    // MARK: Header state (observed from the database)

    var name: String = ""
    var homeInstance: String = ""
    var displayName: String?
    var avatarUrl: URL?
    var bannerUrl: URL?
    var bioMarkdown: String?
    var numberOfPosts: String = ""
    var numberOfComments: String = ""
    var cakeDay: String = ""
    /// Title used for the header / nav bar: display name when set, else name.
    var title: String = ""
    /// Canonical "@name@instance" handle.
    var handle: String = ""

    // MARK: Content state (transient)

    var tab: PersonContentTab = .posts
    var phase: PersonContentPhase = .loading
    private(set) var content = PersonContent()

    // MARK: Private

    @ObservationIgnored
    let serverPersonId: Components.Schemas.PersonID
    @ObservationIgnored
    private let accountKeychainId: String
    @ObservationIgnored
    private let accountService: AccountServiceType
    @ObservationIgnored
    private let sortType: Components.Schemas.SortType

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var contentTask: Task<Void, Never>?

    init(
        personRowId: Int64?,
        serverPersonId: Components.Schemas.PersonID,
        accountKeychainId: String,
        accountService: AccountServiceType,
        appDatabase: AppDatabase
    ) {
        self.serverPersonId = serverPersonId
        self.accountKeychainId = accountKeychainId
        self.accountService = accountService
        sortType = accountService.defaultSortType(forAccountKeychainId: accountKeychainId)

        if let personRowId {
            observationTask = Task { [weak self] in
                for await row in appDatabase.observePersonProfile(personRowId: personRowId) {
                    if Task.isCancelled { break }
                    guard let row else { continue }
                    await MainActor.run { self?.apply(row: row) }
                }
            }
        }
    }

    deinit {
        observationTask?.cancel()
        contentTask?.cancel()
    }

    private func apply(row: PersonProfileRow) {
        name = row.name
        homeInstance = "@\(row.instanceHostname)"
        displayName = row.displayName
        title = row.displayName ?? row.name
        handle = "@\(row.name)@\(row.instanceHostname)"
        avatarUrl = row.avatarUrl.flatMap { URL(string: $0) }
        bannerUrl = row.bannerUrl.flatMap { URL(string: $0) }
        bioMarkdown = row.bio
        numberOfPosts = CommentsFormatter.string(from: row.numberOfPosts)
        numberOfComments = CommentsFormatter.string(from: row.numberOfComments)
        if let createdDate = row.personCreatedDate {
            cakeDay = PersonFormatter.cakeDayString(personCreatedDate: createdDate)
        } else {
            cakeDay = ""
        }
    }

    /// One-line stats summary shown under the handle: post karma, comment
    /// karma, and the cake day.
    var statsText: String {
        var pieces: [String] = []
        let posts = String(
            format: NSLocalizedString("%@ posts", comment: "Person header post count"),
            numberOfPosts
        )
        let comments = String(
            format: NSLocalizedString("%@ comments", comment: "Person header comment count"),
            numberOfComments
        )
        pieces.append(posts)
        pieces.append(comments)
        if !cakeDay.isEmpty {
            pieces.append("🎂 \(cakeDay)")
        }
        return pieces.joined(separator: "  ·  ")
    }

    // MARK: Content loading

    /// Loads (or reloads) the active tab's content. The header observation runs
    /// independently; this only drives the posts/comments lists.
    func loadContent() {
        contentTask?.cancel()
        phase = .loading
        let serverPersonId = serverPersonId
        let sortType = sortType
        contentTask = Task { [weak self] in
            guard let self else { return }
            let lemmyService = accountService.lemmyService(forAccountKeychainId: accountKeychainId)
            do {
                let response = try await lemmyService.fetchPersonContent(
                    serverPersonId: serverPersonId,
                    sort: sortType,
                    page: 1
                )
                if Task.isCancelled { return }
                content = PersonContent(response: response)
                phase = .loaded
            } catch {
                if Task.isCancelled { return }
                logger.error("Fetch person content failed: \(String(describing: error), privacy: .public)")
                content = PersonContent()
                phase = .error
            }
        }
    }

    func tabChanged(_ newTab: PersonContentTab) {
        guard newTab != tab else { return }
        tab = newTab
    }
}
