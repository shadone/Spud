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
import Testing
@testable import SpudDataKit

private typealias Person = Components.Schemas.Person
private typealias PrivateMessage = Components.Schemas.PrivateMessage
private typealias PrivateMessageView = Components.Schemas.PrivateMessageView
private typealias PrivateMessageResponse = Components.Schemas.PrivateMessageResponse

/// Decoded shape of the `createPrivateMessage` request body, so a test can
/// assert the performer sent the right content + recipient.
private struct CreatePrivateMessageRequest: Decodable {
    let content: String
    let recipient_id: Int32
}

/// Stub `ClientTransport` returning a canned `PrivateMessageResponse` for the
/// `createPrivateMessage` operation. Captures the request body so the test can
/// verify the content and recipient that the performer sent, and counts how
/// many times the operation was hit. `failCreate` flips it to a permanent
/// (`badRequest`) failure to exercise the parked-as-failed path.
private final class StubPrivateMessageTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private let failCreate: Bool
    private(set) var createCalls = 0
    private(set) var lastRequest: CreatePrivateMessageRequest?

    init(privateMessageResponse: PrivateMessageResponse, failCreate: Bool = false) throws {
        self.failCreate = failCreate
        let encoder = JSONEncoder()
        // The generated client decodes dates via LemmyDateTranscoder, which
        // accepts the Lemmy 0.19 format: 2024-06-09T11:54:37.981990Z.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(privateMessageResponse)
    }

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "createPrivateMessage" else {
            throw UnexpectedOperation(operationID: operationID)
        }
        createCalls += 1
        if let body {
            let data = try await Data(collecting: body, upTo: .max)
            lastRequest = try? JSONDecoder().decode(CreatePrivateMessageRequest.self, from: data)
        }
        if failCreate {
            // A 400 maps to a permanent LemmyApiError.serverError → parked failed.
            var response = HTTPResponse(status: .badRequest)
            response.headerFields[.contentType] = "application/json"
            let errorJSON = Data(#"{"error":"some_permanent_error","message":"nope"}"#.utf8)
            return (response, HTTPBody(errorJSON))
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(responseJSON))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// Stub transport that fails the first `transientFailures` `createPrivateMessage`
/// calls with a 503 (an undocumented 5xx → `LemmyApiError.unknownServerError` →
/// transient), then succeeds with a canned `PrivateMessageResponse`. Lets a test
/// drive transient-retry-then-success across two drains.
private final class FlakyPrivateMessageTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private let transientFailures: Int
    private(set) var createCalls = 0

    init(privateMessageResponse: PrivateMessageResponse, transientFailures: Int) throws {
        self.transientFailures = transientFailures
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(privateMessageResponse)
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "createPrivateMessage" else {
            throw StubPrivateMessageTransport.UnexpectedOperation(operationID: operationID)
        }
        createCalls += 1
        if createCalls <= transientFailures {
            // 503 is undocumented for this operation → unknownServerError(5xx) → transient.
            let response = HTTPResponse(status: .serviceUnavailable)
            return (response, nil)
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(responseJSON))
    }
}

/// Performer-level coverage for the `.directMessage` outbound kind: the
/// `LemmyComposerPerformer` calls `createPrivateMessage`, imports the confirmed
/// view into the persistent `privateMessage` store, and the generic outbox
/// success path deletes the outbound row. Per-test `AppDatabase.inMemory()`
/// isolates state.
struct OutboundDirectMessagePerformerTests {
    private enum PID {
        static let me: Int64 = 100
        static let alice: Int64 = 200
    }

    private final class FakeReachability: ReachabilityMonitoring, @unchecked Sendable {
        @MainActor var isOnline: Bool = true
        @MainActor var statusStream: AsyncStream<Bool> {
            AsyncStream { $0.finish() }
        }
    }

    private static func person(id: Int64, name: String) -> Person {
        var p = Person.fake
        p.id = Components.Schemas.PersonID(id)
        p.name = name
        p.display_name = name.capitalized
        p.actor_id = "https://\(name).test/u/\(name)"
        return p
    }

    private static func response(
        messageId: Int64,
        creator: Person,
        recipient: Person,
        content: String
    ) -> PrivateMessageResponse {
        let pm = PrivateMessage(
            id: Components.Schemas.PrivateMessageID(messageId),
            creator_id: creator.id,
            recipient_id: recipient.id,
            content: content,
            deleted: false,
            read: false,
            published: Date(timeIntervalSince1970: 1_700_000_000),
            updated: nil,
            ap_id: "https://x.test/private_message/\(messageId)",
            local: true
        )
        let view = PrivateMessageView(private_message: pm, creator: creator, recipient: recipient)
        return PrivateMessageResponse(private_message_view: view)
    }

    /// Seeds instance + site + account (its own person == `me`) and returns
    /// `(accountId, siteId)`.
    private static func seedAccount(_ db: AppDatabase) async throws -> (accountId: Int64, siteId: Int64) {
        try await db.writer.write { write in
            try write.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://seed.test', ?)", arguments: [Date()])
            let instanceId = write.lastInsertedRowID
            try write.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = write.lastInsertedRowID
            try write.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, 'kc-dm', 0, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
            return (write.lastInsertedRowID, siteId)
        }
    }

    private static func makePerformer(
        api: LemmyApi, db: AppDatabase, accountId: Int64, siteId: Int64
    ) -> LemmyComposerPerformer {
        LemmyComposerPerformer(api: api, appDatabase: db, accountId: accountId, siteId: siteId)
    }

    private static func makeService(
        db: AppDatabase, accountId: Int64, performer: OutboundContentPerforming
    ) -> ComposerOutboxService {
        ComposerOutboxService(
            accountId: accountId,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 },
            diagnostics: DiagnosticLogSpy(),
            instance: nil
        )
    }

    @Test
    func directMessageSuccessImportsViewAndDeletesRow() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, siteId) = try await Self.seedAccount(db)

        let me = Self.person(id: PID.me, name: "me")
        let alice = Self.person(id: PID.alice, name: "alice")
        // Server returns the confirmed message (creator = me, recipient = alice).
        let resp = Self.response(messageId: 555, creator: me, recipient: alice, content: "hello alice")
        let transport = try StubPrivateMessageTransport(privateMessageResponse: resp)
        let api = try LemmyApi(
            instanceUrl: #require(URL(string: "https://seed.test")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let performer = Self.makePerformer(api: api, db: db, accountId: accountId, siteId: siteId)
        let svc = Self.makeService(db: db, accountId: accountId, performer: performer)

        // Enqueue a DM send to alice and drain.
        let token = try await db.enqueueOutboundDirectMessage(
            body: "hello alice", recipientServerPersonId: PID.alice, accountId: accountId, now: 0
        )
        await svc.drainOnce()

        // The performer sent createPrivateMessage with the right content + recipient.
        #expect(transport.createCalls == 1)
        #expect(transport.lastRequest?.content == "hello alice")
        #expect(transport.lastRequest?.recipient_id == Int32(PID.alice))

        // The confirmed message landed in the persistent store.
        let stored = db.privateMessagesSync(accountId: accountId)
        #expect(stored.count == 1)
        #expect(stored.first?.serverMessageId == 555)
        #expect(stored.first?.creatorServerPersonId == PID.me)
        #expect(stored.first?.recipientServerPersonId == PID.alice)
        #expect(stored.first?.content == "hello alice")

        // The generic success path deleted the outbound row.
        #expect(try await db.allOutbound(accountId: accountId).isEmpty)
        // Sanity: the token is no longer present.
        let remaining = try await db.allOutbound(accountId: accountId).map(\.clientToken)
        #expect(!remaining.contains(token))
    }

    @Test
    func directMessageTransientFailureRequeuesThenSucceeds() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, siteId) = try await Self.seedAccount(db)

        let me = Self.person(id: PID.me, name: "me")
        let alice = Self.person(id: PID.alice, name: "alice")
        let resp = Self.response(messageId: 777, creator: me, recipient: alice, content: "retry me")
        // First send hits a 503 (transient); the second send succeeds.
        let transport = try FlakyPrivateMessageTransport(privateMessageResponse: resp, transientFailures: 1)
        let api = try LemmyApi(
            instanceUrl: #require(URL(string: "https://seed.test")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let performer = Self.makePerformer(api: api, db: db, accountId: accountId, siteId: siteId)
        let svc = Self.makeService(db: db, accountId: accountId, performer: performer)

        let token = try await db.enqueueOutboundDirectMessage(
            body: "retry me", recipientServerPersonId: PID.alice, accountId: accountId, now: 0
        )

        // First drain: the 503 is transient → the row is re-queued with backoff
        // (NOT parked `.failed`, NOT deleted), attempts incremented, the content kept.
        await svc.drainOnce()
        let afterFirst = try await db.allOutbound(accountId: accountId)
        #expect(afterFirst.count == 1)
        #expect(afterFirst.first?.status == OutboundStatus.queued.rawValue)
        #expect(afterFirst.first?.attempts == 1)
        #expect((afterFirst.first?.nextAttemptAt ?? 0) > 0) // backoff scheduled
        #expect(afterFirst.first?.body == "retry me")
        #expect(afterFirst.first?.recipientServerPersonId == PID.alice)
        // Nothing imported yet — the message has not been confirmed by the server.
        #expect(db.privateMessagesSync(accountId: accountId).isEmpty)
        #expect(transport.createCalls == 1)

        // Second drain (ignoring backoff, as a reachability flip / scheduled
        // retry would): the send succeeds → the confirmed view is imported and
        // the outbound row is deleted.
        await svc.drainAll()
        #expect(transport.createCalls == 2)
        let stored = db.privateMessagesSync(accountId: accountId)
        #expect(stored.count == 1)
        #expect(stored.first?.serverMessageId == 777)
        #expect(stored.first?.content == "retry me")
        #expect(try await db.allOutbound(accountId: accountId).isEmpty)
        let remaining = try await db.allOutbound(accountId: accountId).map(\.clientToken)
        #expect(!remaining.contains(token))
    }

    @Test
    func directMessagePermanentFailureParksAsFailedKeepingContent() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, siteId) = try await Self.seedAccount(db)

        let me = Self.person(id: PID.me, name: "me")
        let alice = Self.person(id: PID.alice, name: "alice")
        let resp = Self.response(messageId: 1, creator: me, recipient: alice, content: "x")
        // 400 → permanent failure.
        let transport = try StubPrivateMessageTransport(privateMessageResponse: resp, failCreate: true)
        let api = try LemmyApi(
            instanceUrl: #require(URL(string: "https://seed.test")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let performer = Self.makePerformer(api: api, db: db, accountId: accountId, siteId: siteId)
        let svc = Self.makeService(db: db, accountId: accountId, performer: performer)
        let failures = await svc.failureEvents

        let token = try await db.enqueueOutboundDirectMessage(
            body: "wont send", recipientServerPersonId: PID.alice, accountId: accountId, now: 0
        )
        await svc.drainOnce()

        // Permanent failure parks the row as `.failed` (kept, not deleted/rolled
        // back) — the content survives for a later retry.
        let rows = try await db.allOutbound(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows.first?.status == OutboundStatus.failed.rawValue)
        #expect(rows.first?.body == "wont send")
        #expect(rows.first?.recipientServerPersonId == PID.alice)
        // Nothing landed in the persistent store.
        #expect(db.privateMessagesSync(accountId: accountId).isEmpty)
        // The failure event named the failed token + DM kind.
        var it = failures.makeAsyncIterator()
        let event = await it.next()
        #expect(event?.clientToken == token)
        #expect(event?.kind == .directMessage)
    }
}
