//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import Testing
@testable import SpudDataKit

/// A stub `ClientTransport` that returns either a 200 OK (with a fake `GetSiteResponse`)
/// or a 403 error, based on the initialisation `mode`.
private final class GetSiteStubTransport: ClientTransport, @unchecked Sendable {
    enum Mode { case success, fail403 }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "getSite" else {
            throw UnexpectedOperation(operationID: operationID)
        }
        switch mode {
        case .success:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let json = try encoder.encode(Lemmy.GetSiteResponse.fake())
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(json))
        case .fail403:
            return (HTTPResponse(status: .init(code: 403)), nil)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// Tests that `LemmyService.getSiteInfo()` records a durable `site.fetchFailed`
/// diagnostic event on failure, and does NOT record one on success.
@MainActor
struct GetSiteDiagnosticsTests {
    private let keychainId = "keychain-1"

    private func makeService(transport: any ClientTransport, spy: DiagnosticLogSpy) throws -> LemmyService {
        let appDatabase = try AppDatabase.inMemory()
        let api = LemmyApi(
            instanceUrl: URL(string: "https://lemmy.test")!,
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        return LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true),
            diagnostics: spy
        )
    }

    @Test
    func fetchSiteFailureEmitsSiteFetchFailedEvent() async throws {
        let spy = DiagnosticLogSpy()
        let service = try makeService(transport: GetSiteStubTransport(mode: .fail403), spy: spy)
        // The error is intentionally discarded; we only care about the diagnostic event.
        try? await service.getSiteInfo()

        let events = spy.events(matching: "site.fetchFailed")
        // swiftformat:disable:next isEmpty
        #expect(events.count == 1, "expected exactly one site.fetchFailed event")
        let event = try #require(events.first)
        #expect(event.category == .site)
        #expect(event.level == .error)
        // Instance host is extracted from the api's instanceUrl, not from the DB
        // (the DB has no account row yet at getSite time).
        #expect(event.instance == "lemmy.test")
        // HTTP status 403 must be surfaced in metadata.
        #expect(event.metadata?["httpStatus"] == "403")
    }

    @Test
    func fetchSiteSuccessDoesNotEmitFailureEvent() async throws {
        let spy = DiagnosticLogSpy()
        let service = try makeService(transport: GetSiteStubTransport(mode: .success), spy: spy)
        // Ignore upsert errors (no account/site rows seeded before getSite).
        _ = try? await service.getSiteInfo()

        #expect(spy.events(matching: "site.fetchFailed").isEmpty, "no failure event on success")
    }
}
