//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// Drives the "Blocked users" / "Blocked communities" management screens. The
/// block lists are sourced from the server (`getSite` -> `my_user`) on appear,
/// not persisted, so they always reflect server truth. Unblocking calls
/// `LemmyService.setBlocked(..., blocked: false)` and removes the row
/// optimistically, reverting on failure.
@MainActor
@Observable
final class BlockedListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case error
    }

    var phase: Phase = .loading
    private(set) var persons: [BlockedList.Person] = []
    private(set) var communities: [BlockedList.Community] = []

    @ObservationIgnored
    private let accountKeychainId: String
    @ObservationIgnored
    private let accountService: AccountServiceType

    init(
        accountKeychainId: String,
        accountService: AccountServiceType
    ) {
        self.accountKeychainId = accountKeychainId
        self.accountService = accountService
    }

    /// Loads (or reloads) the block lists from the server.
    func load() {
        phase = persons.isEmpty && communities.isEmpty ? .loading : phase
        Task { [weak self] in
            guard let self else { return }
            do {
                let blocked = try await accountService
                    .lemmyService(forAccountKeychainId: accountKeychainId)
                    .fetchBlockedList()
                persons = blocked.persons
                communities = blocked.communities
                phase = .loaded
            } catch {
                logger.error("Fetch blocked list failed: \(String(describing: error), privacy: .public)")
                phase = .error
            }
        }
    }

    /// Unblocks the person, removing them from the list optimistically.
    func unblock(person: BlockedList.Person) {
        let index = persons.firstIndex { $0.serverPersonId == person.serverPersonId }
        if let index { persons.remove(at: index) }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: accountKeychainId)
                    .setBlocked(serverPersonId: person.serverPersonId, blocked: false)
            } catch {
                logger.error("Unblock person failed: \(String(describing: error), privacy: .public)")
                // Revert: re-insert at the original position (or append).
                if let index, index <= persons.count {
                    persons.insert(person, at: index)
                } else {
                    persons.append(person)
                }
            }
        }
    }

    /// Unblocks the community, removing it from the list optimistically.
    func unblock(community: BlockedList.Community) {
        let index = communities.firstIndex { $0.serverCommunityId == community.serverCommunityId }
        if let index { communities.remove(at: index) }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: accountKeychainId)
                    .setBlocked(serverCommunityId: community.serverCommunityId, blocked: false)
            } catch {
                logger.error("Unblock community failed: \(String(describing: error), privacy: .public)")
                if let index, index <= communities.count {
                    communities.insert(community, at: index)
                } else {
                    communities.append(community)
                }
            }
        }
    }
}
