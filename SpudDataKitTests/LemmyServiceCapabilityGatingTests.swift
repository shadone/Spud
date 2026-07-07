//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import os
import Testing
@testable import SpudDataKit

// MARK: - Stub transport

/// Counts every `send(...)` call before answering with a generic 400 error, so
/// tests can prove a capability guard fired BEFORE any network request (count
/// stays 0) versus after one was attempted (count > 0). The error response
/// lets `try?`-wrapped calls fail harmlessly past the guard without needing a
/// realistic per-operation success fixture.
private final class CountingTransport: ClientTransport, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    var requestCount: Int {
        lock.withLock { $0 }
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        lock.withLock { $0 += 1 }
        let body = Data(#"{"error":"not_implemented"}"#.utf8)
        var response = HTTPResponse(status: .badRequest)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }
}

// MARK: - Test harness

/// Builds an in-memory-DB-backed `LemmyService` whose account's home site is
/// seeded with `siteVersion` (nil means "not yet mirrored" — the fail-open
/// case), and a `CountingTransport` so tests can assert whether a network
/// request was attempted.
private struct LemmyServiceCapabilityGatingFixture {
    let service: LemmyService
    let appDatabase: AppDatabase
    let transport: CountingTransport
    let keychainId: String

    private static let defaultKeychainId = "keychain-capability-gating-test"

    @MainActor
    static func make(siteVersion: String?, diagnostics: DiagnosticLogging? = nil) async throws -> LemmyServiceCapabilityGatingFixture {
        let keychainId = defaultKeychainId
        let appDatabase = try AppDatabase.inMemory()

        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!, version: siteVersion)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
        }

        let transport = CountingTransport()
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.com")!,
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let service = LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true),
            diagnostics: diagnostics
        )

        return LemmyServiceCapabilityGatingFixture(service: service, appDatabase: appDatabase, transport: transport, keychainId: keychainId)
    }

    /// Reads back the seeded account row, for asserting on a local-mirror
    /// write (e.g. `showNsfw`/`blurNsfw`) after a soft-degraded setter call.
    func fetchAccountRecord() async throws -> AccountRecord? {
        let keychainId = keychainId
        return try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == keychainId).fetchOne(db)
        }
    }
}

/// One gated `LemmyService` operation, packaged so every guarded method can be
/// driven through the same parameterized test instead of duplicating the
/// throw/request-count assertions per method.
struct GatedOperation: CustomTestStringConvertible {
    let testDescription: String
    let run: @Sendable (LemmyService) async throws -> Void
    /// `false` for the one operation (`uploadImage`) whose LemmyKit
    /// implementation bypasses the generated `ClientTransport` entirely (it
    /// hand-builds a `multipart/form-data` request over `URLSession.shared`
    /// for pict-rs) — so `CountingTransport.requestCount` can never observe
    /// its network call and must be excluded from that assertion.
    var routesThroughClientTransport = true
}

/// Every operation the backstop gate must cover, per the Task 4 brief's
/// mapping (method -> `InstanceCapability`). Order matches the brief.
/// Declared at file scope (not a member of the `@MainActor` test suite) so
/// `@Test(arguments:)` can read it without crossing actor isolation.
let gatedOperations: [GatedOperation] = [
    GatedOperation(testDescription: "fetchPersonInfo") { service in
        try await service.fetchPersonInfo(serverPersonId: 1)
    },
    GatedOperation(testDescription: "fetchPersonContent") { service in
        _ = try await service.fetchPersonContent(serverPersonId: 1, sort: .New, page: 1)
    },
    GatedOperation(testDescription: "fetchReplies") { service in
        _ = try await service.fetchReplies(unreadOnly: false, page: 1)
    },
    GatedOperation(testDescription: "fetchMentions") { service in
        _ = try await service.fetchMentions(unreadOnly: false, page: 1)
    },
    GatedOperation(testDescription: "markAllInboxAsRead") { service in
        try await service.markAllInboxAsRead()
    },
    GatedOperation(testDescription: "markReplyAsRead") { service in
        try await service.markReplyAsRead(commentReplyId: 1, read: true)
    },
    GatedOperation(testDescription: "markMentionAsRead") { service in
        try await service.markMentionAsRead(personMentionId: 1, read: true)
    },
    GatedOperation(testDescription: "markPrivateMessageAsRead") { service in
        try await service.markPrivateMessageAsRead(privateMessageId: 1, read: true)
    },
    GatedOperation(testDescription: "fetchPrivateMessages") { service in
        _ = try await service.fetchPrivateMessages(unreadOnly: false, page: 1)
    },
    GatedOperation(testDescription: "sendPrivateMessage") { service in
        _ = try await service.sendPrivateMessage(content: "hi", recipientId: 1)
    },
    GatedOperation(testDescription: "sendDirectMessage") { service in
        _ = try await service.sendDirectMessage(body: "hi", recipientServerPersonId: 1)
    },
    GatedOperation(testDescription: "uploadImage", run: { service in
        _ = try await service.uploadImage(imageData: Data(), fileName: "a.png", mimeType: "image/png")
    }, routesThroughClientTransport: false),
    GatedOperation(testDescription: "saveProfile") { service in
        try await service.saveProfile(
            displayName: nil,
            bio: nil,
            avatar: nil,
            banner: nil,
            showScores: true,
            showBotAccounts: true,
            showReadPosts: true,
            showAvatars: true,
            defaultListingType: .All
        )
    },
    GatedOperation(testDescription: "hidePost") { service in
        try await service.hidePost(serverPostId: 1, hidden: true)
    },
]

/// The soft-degrade operations (Task 5) — background mirrors / scheduler polls
/// with a local source of truth that skip the server push on a gated instance
/// instead of throwing. On a pre-1.0 instance they must all still reach the
/// network — the fail-open constraint applies to them exactly as it does to
/// the throwing `gatedOperations`. All five route through `ClientTransport`.
let softDegradedOperations: [GatedOperation] = [
    GatedOperation(testDescription: "unreadCount") { service in
        _ = try await service.unreadCount()
    },
    GatedOperation(testDescription: "setShowNsfw") { service in
        try await service.setShowNsfw(true)
    },
    GatedOperation(testDescription: "setBlurNsfw") { service in
        try await service.setBlurNsfw(true)
    },
    GatedOperation(testDescription: "setDefaultSortType") { service in
        try await service.setDefaultSortType(.New)
    },
    GatedOperation(testDescription: "markAsRead") { service in
        try await service.markAsRead(serverPostId: 1)
    },
]

// MARK: - Tests

@MainActor
struct LemmyServiceCapabilityGatingTests {
    @Test
    func inboxFetchThrowsUnsupportedOnLemmy1WithoutNetwork() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")
        await #expect(throws: LemmyServiceError.self) {
            try await fixture.service.fetchReplies(unreadOnly: false, page: 1)
        }
        #expect(fixture.transport.requestCount == 0)
    }

    @Test
    func inboxFetchProceedsOn019() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "0.19.11")
        _ = try? await fixture.service.fetchReplies(unreadOnly: false, page: 1)
        #expect(fixture.transport.requestCount > 0)
    }

    @Test
    func unknownVersionFailsOpen() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: nil)
        _ = try? await fixture.service.fetchReplies(unreadOnly: false, page: 1)
        #expect(fixture.transport.requestCount > 0)
    }

    /// Every gated operation must throw `.unsupportedByInstance` BEFORE any
    /// network call when the home instance is a Lemmy 1.0 v3-shim server —
    /// proving the guard is genuinely the first statement, not just present
    /// somewhere in the method.
    @Test(arguments: gatedOperations)
    func gatedOperationThrowsUnsupportedOnLemmy1WithoutNetwork(_ operation: GatedOperation) async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        var thrown: Error?
        do {
            try await operation.run(fixture.service)
        } catch {
            thrown = error
        }

        let serviceError = try #require(thrown as? LemmyServiceError)
        guard case .unsupportedByInstance = serviceError else {
            Issue.record("expected .unsupportedByInstance, got \(serviceError)")
            return
        }
        #expect(fixture.transport.requestCount == 0, "\(operation.testDescription) must not reach the network")
    }

    /// Same operations must proceed to the network on a pre-1.0 (fully
    /// supported) instance — the guard must not over-block. Excludes
    /// `uploadImage` (see `GatedOperation.routesThroughClientTransport`).
    @Test(arguments: gatedOperations.filter(\.routesThroughClientTransport))
    func gatedOperationProceedsOn019(_ operation: GatedOperation) async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "0.19.11")
        _ = try? await operation.run(fixture.service)
        #expect(fixture.transport.requestCount > 0, "\(operation.testDescription) must reach the network on 0.19")
    }

    /// `sendDirectMessage` guards BEFORE enqueueing, so a gated instance must
    /// never park content in the composer outbox table.
    @Test
    func sendDirectMessageDoesNotEnqueueOnLemmy1() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        await #expect(throws: LemmyServiceError.self) {
            _ = try await fixture.service.sendDirectMessage(body: "hi", recipientServerPersonId: 1)
        }

        let rows = try await fixture.appDatabase.writer.read { db in
            try OutboundContentRecord.fetchAll(db)
        }
        #expect(rows.isEmpty, "gated sendDirectMessage must not enqueue any outboundContent row")
    }

    /// The gate records a durable `capability.blocked` diagnostic event
    /// (matching the `site.fetchFailed` idiom in `LemmyService.swift`) so a
    /// blocked operation is observable in About -> Logs.
    @Test
    func blockedCapabilityEmitsCapabilityBlockedEvent() async throws {
        let spy = DiagnosticLogSpy()
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18", diagnostics: spy)

        _ = try? await fixture.service.fetchReplies(unreadOnly: false, page: 1)

        let events = spy.events(matching: "capability.blocked")
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.level == .info)
        #expect(event.instance == "example.com")
        #expect(event.metadata?["capability"] == InstanceCapability.inbox.rawValue)
    }

    // MARK: - Soft-degrade paths (Task 5)

    //
    // These four are background mirrors / scheduler polls with a local source
    // of truth, so a gated instance must SKIP silently rather than throw.

    @Test
    func unreadCountReturnsZeroOnLemmy1WithoutNetwork() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        let count = try await fixture.service.unreadCount()

        #expect(count == .zero)
        #expect(fixture.transport.requestCount == 0)
    }

    /// All soft-degrade operations must proceed to the network on a pre-1.0
    /// (fully supported) instance — the skip must not over-block, mirroring
    /// `gatedOperationProceedsOn019` for the throwing set.
    @Test(arguments: softDegradedOperations)
    func softDegradedOperationProceedsOn019(_ operation: GatedOperation) async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "0.19.11")
        _ = try? await operation.run(fixture.service)
        #expect(fixture.transport.requestCount > 0, "\(operation.testDescription) must reach the network on 0.19")
    }

    @Test
    func setShowNsfwSkipsServerPushButMirrorsLocallyOnLemmy1() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        try await fixture.service.setShowNsfw(true)

        #expect(fixture.transport.requestCount == 0)
        let account = try await fixture.fetchAccountRecord()
        #expect(account?.showNsfw == true)
    }

    @Test
    func setBlurNsfwSkipsServerPushButMirrorsLocallyOnLemmy1() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        try await fixture.service.setBlurNsfw(true)

        #expect(fixture.transport.requestCount == 0)
        let account = try await fixture.fetchAccountRecord()
        #expect(account?.blurNsfw == true)
    }

    @Test
    func setDefaultSortTypeSkipsServerPushOnLemmy1() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        try await fixture.service.setDefaultSortType(.New)

        #expect(fixture.transport.requestCount == 0)
    }

    @Test
    func markAsReadSkipsServerPushOnLemmy1() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        try await fixture.service.markAsRead(serverPostId: 1)

        #expect(fixture.transport.requestCount == 0)
    }
}
