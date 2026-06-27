//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Unit tests for the `LoginResponse` -> `AccountServiceRegisterResult` mapping,
/// the load-bearing logic that decides whether a successful (HTTP 200)
/// registration logged the user in or landed in a pending / verify-email state
/// the UI must surface.
struct AccountServiceRegisterResultTests {
    @Test
    func jwtPresentMapsToLoggedIn() {
        let response = Components.Schemas.LoginResponse.fake(jwt: "a.jwt.token")
        #expect(AccountServiceRegisterResult(response: response) == .loggedIn)
    }

    @Test
    func jwtPresentTakesPrecedenceOverPendingFlags() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: "a.jwt.token",
            registrationCreated: true,
            verifyEmailSent: true
        )
        #expect(AccountServiceRegisterResult(response: response) == .loggedIn)
    }

    @Test
    func verifyEmailSentMapsToVerifyEmail() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: nil,
            registrationCreated: true,
            verifyEmailSent: true
        )
        #expect(AccountServiceRegisterResult(response: response) == .verifyEmail)
    }

    @Test
    func registrationCreatedWithoutEmailMapsToApplicationPending() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: nil,
            registrationCreated: true,
            verifyEmailSent: false
        )
        #expect(AccountServiceRegisterResult(response: response) == .applicationPending)
    }

    @Test
    func noJwtNoFlagsMapsToPending() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: nil,
            registrationCreated: false,
            verifyEmailSent: false
        )
        #expect(AccountServiceRegisterResult(response: response) == .pending)
    }
}
