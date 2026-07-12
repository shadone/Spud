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
    GatedOperation(testDescription: "markInboxItemAsRead(commentReply)") { service in
        try await service.markInboxItemAsRead(reference: .commentReply(1), read: true)
    },
    GatedOperation(testDescription: "markInboxItemAsRead(personMention)") { service in
        try await service.markInboxItemAsRead(reference: .personMention(1), read: true)
    },
    GatedOperation(testDescription: "markPrivateMessageAsRead") { service in
        try await service.markPrivateMessageAsRead(privateMessageId: 1, read: true)
    },
    GatedOperation(testDescription: "fetchPrivateMessages") { service in
        _ = try await service.fetchPrivateMessages(unreadOnly: false, pageCursor: nil)
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
            avatar: .unchanged,
            banner: .unchanged,
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

/// The gating that once withheld seven operations on a Lemmy 1.0 (v3-shim)
/// instance has been RETIRED: Spud speaks native v4, so `InstanceCapabilities`
/// now reports every capability available on every Lemmy version. These tests
/// therefore assert the NEW reality — that the previously-gated operations no
/// longer short-circuit on a 1.0 instance — alongside the unchanged fail-open
/// behavior on a pre-1.0 instance.
///
/// The fixture builds a v3-dispatching `LemmyApi` over a `CountingTransport` that
/// answers every request with a 400, so an operation that "proceeds" reaches the
/// network and then throws a plain `apiError`; what matters is that it is no
/// longer blocked BEFORE the network by the capability backstop.
@MainActor
struct LemmyServiceCapabilityGatingTests {
    @Test
    func inboxFetchNoLongerBlocksOnLemmy1() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")
        // No longer gated: the fetch reaches the network (and fails on the 400
        // stub) instead of throwing .unsupportedByInstance before any request.
        _ = try? await fixture.service.fetchReplies(unreadOnly: false, page: 1)
        #expect(fixture.transport.requestCount > 0)
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

    /// After retiring the gating, NO previously-gated operation throws
    /// `.unsupportedByInstance` on a Lemmy 1.0 instance — the capability backstop
    /// stays in the code but never fires, because every capability is available.
    /// Each op may still throw a plain network error against the 400 stub, or
    /// enqueue, or succeed; only `.unsupportedByInstance` is disallowed.
    @Test(arguments: gatedOperations)
    func previouslyGatedOperationDoesNotBlockOnLemmy1(_ operation: GatedOperation) async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        do {
            try await operation.run(fixture.service)
        } catch let error as LemmyServiceError {
            if case .unsupportedByInstance = error {
                Issue.record("\(operation.testDescription) is still gated on Lemmy 1.0 after the gating was retired")
            }
            // Any other LemmyServiceError (e.g. the 400-stub apiError) is expected.
        } catch {
            // A non-LemmyServiceError is also fine — it is not the gate firing.
        }
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

    /// `sendDirectMessage` is no longer gated on Lemmy 1.0, so it enqueues an
    /// outbound-content row (the durable/optimistic send) rather than throwing
    /// `.unsupportedByInstance` before enqueueing.
    @Test
    func sendDirectMessageEnqueuesOnLemmy1() async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")

        _ = try await fixture.service.sendDirectMessage(body: "hi", recipientServerPersonId: 1)

        let rows = try await fixture.appDatabase.writer.read { db in
            try OutboundContentRecord.fetchAll(db)
        }
        #expect(!rows.isEmpty, "ungated sendDirectMessage must enqueue an outboundContent row")
    }

    /// The capability gate no longer fires on Lemmy 1.0, so no `capability.blocked`
    /// diagnostic event is recorded there. The event idiom (matching
    /// `site.fetchFailed` in `LemmyService.swift`) is kept for a future gated
    /// capability.
    @Test
    func noCapabilityBlockedEventOnLemmy1() async throws {
        let spy = DiagnosticLogSpy()
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18", diagnostics: spy)

        _ = try? await fixture.service.fetchReplies(unreadOnly: false, page: 1)

        #expect(spy.events(matching: "capability.blocked").isEmpty)
    }

    // MARK: - Previously soft-degraded paths

    //
    // These background mirrors / scheduler polls once SKIPPED the server push on
    // a gated instance. With the gating retired, the skip is inert: on Lemmy 1.0
    // they now proceed to the network exactly as they always did on a pre-1.0
    // instance.

    /// All soft-degrade operations reach the network on a pre-1.0 (fully
    /// supported) instance — unchanged by the retirement.
    @Test(arguments: softDegradedOperations)
    func softDegradedOperationProceedsOn019(_ operation: GatedOperation) async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "0.19.11")
        _ = try? await operation.run(fixture.service)
        #expect(fixture.transport.requestCount > 0, "\(operation.testDescription) must reach the network on 0.19")
    }

    /// And now also reach the network on a Lemmy 1.0 instance — the soft-degrade
    /// skip no longer short-circuits them, because their capabilities are
    /// available.
    @Test(arguments: softDegradedOperations)
    func softDegradedOperationProceedsOnLemmy1(_ operation: GatedOperation) async throws {
        let fixture = try await LemmyServiceCapabilityGatingFixture.make(siteVersion: "1.0.0-alpha.18")
        _ = try? await operation.run(fixture.service)
        #expect(fixture.transport.requestCount > 0, "\(operation.testDescription) must reach the network on Lemmy 1.0")
    }
}
