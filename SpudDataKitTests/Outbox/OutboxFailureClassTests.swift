//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

struct OutboxFailureClassTests {
    @Test
    func offlineIsTransient() {
        #expect(OutboxFailureClass.classify(LemmyServiceError.requiresAuthentication, isOnline: false) == .transient)
    }

    @Test
    func requiresAuthOnlineIsPermanent() {
        #expect(OutboxFailureClass.classify(LemmyServiceError.requiresAuthentication, isOnline: true) == .permanent)
    }

    @Test
    func timeoutIsTransient() {
        #expect(OutboxFailureClass.classify(URLError(.timedOut), isOnline: true) == .transient)
    }

    @Test
    func unauthorizedApiErrorIsPermanent() {
        #expect(OutboxFailureClass.classify(LemmyApiError.unauthorized(message: nil), isOnline: true) == .permanent)
    }
}
