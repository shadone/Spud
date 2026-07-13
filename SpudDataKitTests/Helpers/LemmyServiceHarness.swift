//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OpenAPIRuntime
@testable import SpudDataKit

/// Canonical `LemmyService` builder for tests: fake instance URL + JWT,
/// injectable transport. Replaces ~16 identical private `makeService` copies.
@MainActor
enum LemmyServiceHarness {
    static func make(
        accountKeychainId: String,
        appDatabase: AppDatabase,
        accountIsSignedOut: Bool = false,
        transport: any ClientTransport,
        apiVersion: ApiVersion = .v3
    ) -> LemmyService {
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.com")!,
            credential: accountIsSignedOut ? nil : LemmyCredential(jwt: "fake-jwt"),
            transport: transport,
            apiVersion: apiVersion
        )
        return LemmyService(
            accountKeychainId: accountKeychainId,
            accountIsSignedOut: accountIsSignedOut,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )
    }
}
