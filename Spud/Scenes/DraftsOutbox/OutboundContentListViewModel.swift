//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import OSLog
import SpudDataKit
import SpudUtilKit

private let logger = Logger.app

/// A single section in the Drafts & Outbox list.
struct OutboundSection: Equatable {
    enum Kind: Equatable {
        /// Status == failed. Shown first so failed items are immediately visible.
        case failed
        /// Status == queued or sending.
        case sending
        /// Status == draft.
        case draft
    }

    let kind: Kind
    let rows: [OutboundContentRecord]
}

@MainActor
@Observable
final class OutboundContentListViewModel {
    typealias OwnDependencies = HasAccountService & HasAppDatabase
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    private let accountScope: AccountScope

    @ObservationIgnored
    private let accountKeychainId: String

    /// Grouped + ordered sections: Failed first, Sending second, Drafts third.
    private(set) var sections: [OutboundSection] = []

    /// True when the observation has delivered at least one (possibly empty) update.
    private(set) var isLoaded = false

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    // MARK: Init

    init(accountKeychainId: String, dependencies: Dependencies) {
        self.accountKeychainId = accountKeychainId
        self.dependencies = dependencies
        accountScope = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId)
        startObservation()
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: Observation

    private func startObservation() {
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in dependencies.appDatabase.observeOutboundContent(accountKeychainId: accountKeychainId) {
                if Task.isCancelled { break }
                apply(rows: rows)
            }
        }
    }

    private func apply(rows: [OutboundContentRecord]) {
        let failed = rows.filter { OutboundStatus(rawValue: $0.status) == .failed }
        let sending = rows.filter {
            let s = OutboundStatus(rawValue: $0.status)
            return s == .queued || s == .sending
        }
        let drafts = rows.filter { OutboundStatus(rawValue: $0.status) == .draft }

        var result: [OutboundSection] = []
        if !failed.isEmpty { result.append(OutboundSection(kind: .failed, rows: failed)) }
        if !sending.isEmpty { result.append(OutboundSection(kind: .sending, rows: sending)) }
        if !drafts.isEmpty { result.append(OutboundSection(kind: .draft, rows: drafts)) }

        sections = result
        isLoaded = true
    }

    // MARK: Actions

    func retry(clientToken: String) {
        let scope = accountScope
        Task { await scope.lemmyService.retryComposition(clientToken: clientToken) }
    }

    func discard(clientToken: String) {
        let scope = accountScope
        Task { await scope.lemmyService.discardComposition(clientToken: clientToken) }
    }
}
