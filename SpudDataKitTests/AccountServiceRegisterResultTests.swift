//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import XCTest
@testable import SpudDataKit

/// Unit tests for the `LoginResponse` -> `AccountServiceRegisterResult` mapping,
/// the load-bearing logic that decides whether a successful (HTTP 200)
/// registration logged the user in or landed in a pending / verify-email state
/// the UI must surface.
final class AccountServiceRegisterResultTests: XCTestCase {
    func testJwtPresentMapsToLoggedIn() {
        let response = Components.Schemas.LoginResponse.fake(jwt: "a.jwt.token")
        XCTAssertEqual(AccountServiceRegisterResult(response: response), .loggedIn)
    }

    func testJwtPresentTakesPrecedenceOverPendingFlags() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: "a.jwt.token",
            registrationCreated: true,
            verifyEmailSent: true
        )
        XCTAssertEqual(AccountServiceRegisterResult(response: response), .loggedIn)
    }

    func testVerifyEmailSentMapsToVerifyEmail() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: nil,
            registrationCreated: true,
            verifyEmailSent: true
        )
        XCTAssertEqual(AccountServiceRegisterResult(response: response), .verifyEmail)
    }

    func testRegistrationCreatedWithoutEmailMapsToApplicationPending() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: nil,
            registrationCreated: true,
            verifyEmailSent: false
        )
        XCTAssertEqual(AccountServiceRegisterResult(response: response), .applicationPending)
    }

    func testNoJwtNoFlagsMapsToPending() {
        let response = Components.Schemas.LoginResponse.fake(
            jwt: nil,
            registrationCreated: false,
            verifyEmailSent: false
        )
        XCTAssertEqual(AccountServiceRegisterResult(response: response), .pending)
    }
}
