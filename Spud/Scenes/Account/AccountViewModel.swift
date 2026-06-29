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

    // MARK: Profile header (observed once the own person resolves)

    /// The signed-in account's display name (or username when no display name is
    /// set). Empty until the profile resolves.
    private(set) var displayName: String = ""

    /// The signed-in account's canonical `@name@instance` handle. Empty until
    /// the profile resolves.
    private(set) var handle: String = ""

    /// The signed-in account's avatar URL, or nil for the hue-tile fallback.
    private(set) var avatarUrl: URL?

    /// Number of real signed-in (non-anonymous) accounts, shown as the "N signed
    /// in" subtitle on the Switch account row.
    private(set) var signedInAccountCount: Int = 0

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
    @ObservationIgnored
    private var accountsTask: Task<Void, Never>?
    /// Live observation of the own person row, restarted whenever the resolved
    /// own person changes (e.g. after a login or account switch).
    @ObservationIgnored
    private var profileTask: Task<Void, Never>?
    @ObservationIgnored
    private var observedProfileRowId: Int64?

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

        // The "N signed in" subtitle tracks the account list live so it updates
        // after a login / logout / account add without a manual refresh.
        accountsTask = Task { [weak self] in
            for await accounts in appDatabase.observeAccounts() {
                if Task.isCancelled { break }
                let count = accounts.filter { !$0.isSignedOutAccountType }.count
                await MainActor.run { self?.signedInAccountCount = count }
            }
        }
    }

    deinit {
        observationTask?.cancel()
        accountsTask?.cancel()
        profileTask?.cancel()
    }

    private func apply(record: AccountRecord) {
        accountKeychainId = record.accountKeychainId
        isSignedIn = !record.isSignedOutAccountType
        instanceHostname = appDatabase.accountInstanceActorIdSync(forKeychainId: record.accountKeychainId)
            .flatMap { URL(string: $0)?.host } ?? ""

        if isSignedIn, let ids = appDatabase.accountOwnPersonIdsSync(forKeychainId: record.accountKeychainId) {
            ownPerson = OwnPerson(personRowId: ids.personRowId, serverPersonId: ids.serverPersonId)
            startProfileObservation(personRowId: ids.personRowId)
        } else {
            ownPerson = nil
            stopProfileObservation()
        }
    }

    /// Starts (or restarts) the live observation of the own person's profile row
    /// so the header's display name / handle / avatar stay current. No-op if it's
    /// already observing the same row.
    private func startProfileObservation(personRowId: Int64) {
        guard observedProfileRowId != personRowId else { return }
        observedProfileRowId = personRowId
        profileTask?.cancel()
        let appDatabase = appDatabase
        profileTask = Task { [weak self] in
            for await row in appDatabase.observePersonProfile(personRowId: personRowId) {
                if Task.isCancelled { break }
                guard let row else { continue }
                await MainActor.run { self?.applyProfile(row: row) }
            }
        }
    }

    private func stopProfileObservation() {
        profileTask?.cancel()
        profileTask = nil
        observedProfileRowId = nil
        displayName = ""
        handle = ""
        avatarUrl = nil
    }

    private func applyProfile(row: PersonProfileRow) {
        displayName = row.displayName ?? row.name
        handle = "@\(row.name)@\(row.instanceHostname)"
        avatarUrl = row.avatarUrl.flatMap { URL(string: $0) }
    }

    func logout() {
        let keychainId = accountKeychainId
        guard !keychainId.isEmpty else { return }
        accountService.logout(forAccountKeychainId: keychainId)
    }
}
