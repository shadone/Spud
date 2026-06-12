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

/// Drives the Account tab. Observes the default account so the screen flips
/// between its signed-in and signed-out layouts live (e.g. after a login,
/// account switch, or logout). Holds only the identity needed to bring up the
/// embedded Person profile and the account actions.
@MainActor
@Observable
final class AccountViewModel {
    /// True when the current default account is a real signed-in account
    /// (not the signed-out / anonymous placeholder).
    var isSignedIn: Bool = false

    /// The default account's keychain id. Empty until the first snapshot.
    private(set) var accountKeychainId: String = ""

    /// Home instance hostname of the current account, e.g. "lemmy.world".
    private(set) var instanceHostname: String = ""

    /// Resolved identity of the signed-in account's own person, once its
    /// `MyUserInfo` (and person row) has been imported. Nil for signed-out
    /// accounts or before the import lands.
    private(set) var ownPerson: OwnPerson?

    struct OwnPerson: Equatable {
        let personRowId: Int64
        let serverPersonId: Int64
    }

    @ObservationIgnored
    private let accountService: AccountServiceType
    @ObservationIgnored
    private let appDatabase: AppDatabase

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    init(
        accountService: AccountServiceType,
        appDatabase: AppDatabase
    ) {
        self.accountService = accountService
        self.appDatabase = appDatabase

        observationTask = Task { [weak self] in
            for await record in appDatabase.observeDefaultAccount() {
                if Task.isCancelled { break }
                guard let record else { continue }
                await MainActor.run { self?.apply(record: record) }
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func apply(record: AccountRecord) {
        accountKeychainId = record.accountKeychainId
        isSignedIn = !record.isSignedOutAccountType
        instanceHostname = appDatabase.accountInstanceActorIdSync(forKeychainId: record.accountKeychainId)
            .flatMap { URL(string: $0)?.host } ?? ""

        if isSignedIn, let ids = appDatabase.accountOwnPersonIdsSync(forKeychainId: record.accountKeychainId) {
            ownPerson = OwnPerson(personRowId: ids.personRowId, serverPersonId: ids.serverPersonId)
        } else {
            ownPerson = nil
        }
    }

    func logout() {
        let keychainId = accountKeychainId
        guard !keychainId.isEmpty else { return }
        accountService.logout(forAccountKeychainId: keychainId)
    }
}
