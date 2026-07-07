//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
@testable import Spud

// MARK: - Fake

/// Minimal `AccountServiceType` stub that throws `PlatformUnsupportedError`
/// from `register` so the VM's catch branch can be exercised without network.
private final class BlockingAccountService: AccountServiceType {
    let error: PlatformUnsupportedError

    init(error: PlatformUnsupportedError) {
        self.error = error
    }

    func register(
        atInstance _: InstanceActorId,
        username _: String,
        email _: String?,
        password _: String,
        passwordVerify _: String,
        showNsfw _: Bool,
        captchaUuid _: String?,
        captchaAnswer _: String?,
        answer _: String?
    ) async throws -> AccountServiceRegisterResult {
        throw error
    }

    // MARK: Unused stubs

    func accountForSignedOut(forInstance _: InstanceActorId, isServiceAccount _: Bool) -> String {
        ""
    }

    func signInAsSignedOut(atInstance _: InstanceActorId) { }
    #if DEBUG
    func seedSignedInDefaultAccount(atInstance _: InstanceActorId) { }
    #endif
    func login(atInstance _: InstanceActorId, username _: String, password _: String, totp2faToken _: String?) async throws { }
    func passwordReset(atInstance _: InstanceActorId, email _: String) async throws { }
    func logout(forAccountKeychainId _: String) { }
    func removeAccount(forAccountKeychainId _: String) { }
    func currentDefaultAccountKeychainId() -> String? {
        nil
    }

    func isSignedOut(forAccountKeychainId _: String) -> Bool {
        false
    }

    func setDefaultAccount(forAccountKeychainId _: String) { }
    func accountKeychainId(forInstance _: InstanceActorId) -> String {
        ""
    }

    func defaultListingType(forAccountKeychainId _: String) -> Components.Schemas.ListingType {
        .All
    }

    func defaultSortType(forAccountKeychainId _: String) -> Components.Schemas.SortType {
        .Hot
    }

    func setDefaultSortType(_: Components.Schemas.SortType, forAccountKeychainId _: String) { }
    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        nil
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        .allAvailable
    }

    func refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId _: String) { }
    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        fatalError()
    }
}

// MARK: - Tests

/// Verifies that `RegisterViewModel.register()` sets `blockedPlatform` when
/// `accountService.register` throws `PlatformUnsupportedError`.
@MainActor
struct RegisterViewModelBlockTests {
    private func makeRow() -> SiteListRow {
        SiteListRow(
            id: 1,
            instance: InstanceActorId(from: "piefed.social")!,
            hostname: "piefed.social",
            name: nil,
            descriptionText: nil,
            iconUrl: nil
        )
    }

    @Test
    func register_throwsPlatformUnsupported_setsBlockedPlatform() async {
        let blocked = PlatformUnsupportedError(
            software: .piefed,
            displayName: "PieFed",
            version: "1.0",
            host: "piefed.social"
        )
        let accountService = BlockingAccountService(error: blocked)
        let viewModel = RegisterViewModel(row: makeRow(), accountService: accountService)
        viewModel.username = "alice"
        viewModel.password = "s3cr3t!"
        viewModel.passwordVerify = "s3cr3t!"

        await viewModel.register()

        #expect(viewModel.blockedPlatform == blocked)
        #expect(viewModel.outcomeMessage == nil)
    }
}
