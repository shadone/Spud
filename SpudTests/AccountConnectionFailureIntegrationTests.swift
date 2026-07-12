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

/// Minimal `AccountServiceType` stub whose `login`/`register` throw a
/// caller-supplied error, so `LoginViewModel`/`RegisterViewModel`'s error
/// classification can be exercised end-to-end (not just the pure classifier)
/// without any network. Mirrors `RegisterViewModelBlockTests`'
/// `BlockingAccountService`.
private final class ThrowingAccountService: AccountServiceType {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func login(atInstance _: InstanceActorId, username _: String, password _: String, totp2faToken _: String?) async throws {
        throw error
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

    func defaultListingType(forAccountKeychainId _: String) -> Lemmy.ListingType {
        .All
    }

    func defaultSortType(forAccountKeychainId _: String) -> Lemmy.SortType {
        .Hot
    }

    func setDefaultSortType(_: Lemmy.SortType, forAccountKeychainId _: String) { }
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

/// End-to-end confirmation (beyond the pure `AccountConnectionFailureTests`)
/// that a typo'd/unreachable custom instance surfaces the connection message,
/// not "Incorrect username or password" / a generic sign-up failure.
@MainActor
struct AccountConnectionFailureIntegrationTests {
    private func makeRow() -> SiteListRow {
        SiteListRow.forTypedInstance(InstanceActorId(from: "lemmy.example.com")!)
    }

    @Test
    func login_networkFailure_showsConnectionMessage() async {
        let accountService = ThrowingAccountService(
            error: AccountServiceLoginError.apiError(.network(URLError(.cannotFindHost)))
        )
        let dependencies = FakeLoginDependencies(
            accountService: accountService,
            alertService: AlertService(),
            imageService: StaticImageService()
        )
        let viewModel = LoginViewModel(row: makeRow(), dependencies: dependencies)
        viewModel.username = "alice"
        viewModel.password = "s3cr3t!"

        await viewModel.login()

        #expect(viewModel.loginError == AccountConnectionFailure.message(host: "lemmy.example.com"))
    }

    @Test
    func login_invalidCredentials_showsCredentialsMessage() async {
        let accountService = ThrowingAccountService(error: AccountServiceLoginError.invalidLogin)
        let dependencies = FakeLoginDependencies(
            accountService: accountService,
            alertService: AlertService(),
            imageService: StaticImageService()
        )
        let viewModel = LoginViewModel(row: makeRow(), dependencies: dependencies)
        viewModel.username = "alice"
        viewModel.password = "wrong"

        await viewModel.login()

        #expect(viewModel.loginError == "Incorrect username or password.")
    }

    @Test
    func register_networkFailure_showsConnectionMessage() async {
        let accountService = ThrowingAccountService(
            error: AccountServiceRegisterError.apiError(.network(URLError(.timedOut)))
        )
        let viewModel = RegisterViewModel(row: makeRow(), accountService: accountService)
        viewModel.username = "alice"
        viewModel.password = "s3cr3t!"
        viewModel.passwordVerify = "s3cr3t!"

        await viewModel.register()

        #expect(viewModel.outcomeMessage == AccountConnectionFailure.message(host: "lemmy.example.com"))
    }

    @Test
    func register_rejected_showsRejectionMessage() async {
        let accountService = ThrowingAccountService(
            error: AccountServiceRegisterError.rejected(message: nil)
        )
        let viewModel = RegisterViewModel(row: makeRow(), accountService: accountService)
        viewModel.username = "alice"
        viewModel.password = "s3cr3t!"
        viewModel.passwordVerify = "s3cr3t!"

        await viewModel.register()

        #expect(viewModel.outcomeMessage != AccountConnectionFailure.message(host: "lemmy.example.com"))
        #expect(viewModel.outcomeMessage != nil)
    }
}

@MainActor
private struct FakeLoginDependencies: HasVoid, HasAccountService, HasAlertService, HasImageService {
    let accountService: AccountServiceType
    let alertService: AlertServiceType
    let imageService: ImageServiceType
}
