//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

/// Slice 1 coverage for the persistent private-message store: the importer
/// (`upsertPrivateMessages`) and the two read observations
/// (`observeConversations` / `observeMessages`). Per-test `AppDatabase.inMemory()`
/// isolates state, so the suite needs no `.serialized`.
struct PrivateMessageStoreTests {
    // MARK: - Fixtures

    /// Server person ids used across the tests. `me` is the account holder;
    /// `alice` / `bob` are correspondents.
    private enum PID {
        static let me: Int64 = 100
        static let alice: Int64 = 200
        static let bob: Int64 = 300
    }

    /// Seeds instance + site + account and returns the account row id. When
    /// `ownServerPersonId` is non-nil, also inserts that person row and links
    /// `account.personId` to it (a person ROW id, the same shape the real
    /// AccountImporter writes) so `observeConversations` can resolve the
    /// account's own server person id and derive the correspondent. nil leaves
    /// the account with no own-person, exercising the creator fallback.
    private static func seedAccount(_ db: Database, keychainId: String, ownServerPersonId: Int64?) throws -> (accountId: Int64, siteId: Int64) {
        try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
        let instanceId = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
        let siteId = db.lastInsertedRowID

        var personRowId: Int64?
        if let ownServerPersonId {
            try db.execute(sql: """
                INSERT INTO person (siteId, personId, name, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, ?, 'me', 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteId, ownServerPersonId, Date(), Date()])
            personRowId = db.lastInsertedRowID
        }

        try db.execute(sql: """
            INSERT INTO account (siteId, personId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
            VALUES (?, ?, ?, 0, 0, 0, ?, ?)
            """, arguments: [siteId, personRowId, keychainId, Date(), Date()])
        let accountId = db.lastInsertedRowID
        return (accountId, siteId)
    }

    private static func person(id: Int64, name: String, displayName: String?, avatar: String?) -> Lemmy.Person {
        // Neutral `Person` fields are `let`, so build a fresh value rather than
        // mutating `.fake`.
        Lemmy.Person(
            id: id,
            name: name,
            displayName: displayName,
            avatarUrl: avatar,
            bannerUrl: nil,
            bio: nil,
            apId: "https://\(name).test/u/\(name)",
            matrixUserId: nil,
            botAccount: false,
            deleted: false,
            local: true,
            publishedAt: Date(timeIntervalSince1970: 1_683_349_689),
            updatedAt: nil,
            postCount: 0,
            commentCount: 0
        )
    }

    /// Builds an ``IncomingPrivateMessage`` (a neutral ``LemmyKit/PrivateMessageView``
    /// paired with its read state). The neutral `PrivateMessage` dropped v3's bare
    /// `read` bool, so read state rides on the wrapping `IncomingPrivateMessage`,
    /// which is what `upsertPrivateMessages` now consumes.
    private static func view(
        messageId: Int64,
        creator: Lemmy.Person,
        recipient: Lemmy.Person,
        content: String,
        published: Date,
        read: Bool,
        deleted: Bool = false
    ) -> IncomingPrivateMessage {
        let pm = LemmyKit.PrivateMessage(
            id: messageId,
            creatorId: creator.id,
            recipientId: recipient.id,
            content: content,
            deleted: deleted,
            deletedByRecipient: false,
            removed: false,
            local: true,
            apId: "https://x.test/private_message/\(messageId)",
            publishedAt: published,
            updatedAt: nil
        )
        let pmView = Lemmy.PrivateMessageView(privateMessage: pm, creator: creator, recipient: recipient)
        return IncomingPrivateMessage(view: pmView, isRead: read)
    }

    private static func firstConversations(_ stream: AsyncStream<[PrivateMessageConversationRow]>) async -> [PrivateMessageConversationRow] {
        for await rows in stream {
            return rows
        }
        return []
    }

    private static func firstMessages(_ stream: AsyncStream<[PrivateMessageRow]>) async -> [PrivateMessageRow] {
        for await rows in stream {
            return rows
        }
        return []
    }

    // MARK: - Importer

    @Test
    func importerUpsertsPersonsAndMessages() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let me = Self.person(id: PID.me, name: "me", displayName: "Me", avatar: nil)
        let alice = Self.person(id: PID.alice, name: "alice", displayName: "Alice", avatar: "https://a.test/avatar.png")

        let accountId = try await appDatabase.writer.write { db -> Int64 in
            try Self.seedAccount(db, keychainId: "kc-1", ownServerPersonId: PID.me).accountId
        }

        try await appDatabase.upsertPrivateMessages(
            [
                Self.view(messageId: 1, creator: alice, recipient: me, content: "hi", published: Date(timeIntervalSince1970: 1000), read: false),
            ],
            accountId: accountId
        )

        let (messages, persons) = try await appDatabase.writer.read { db -> (Int, Int) in
            let m = try PrivateMessageRecord.fetchCount(db)
            let p = try PersonRecord.fetchCount(db)
            return (m, p)
        }
        #expect(messages == 1)
        // Both participants (me + alice) were upserted into the person table.
        #expect(persons == 2)

        let stored = appDatabase.privateMessagesSync(accountId: accountId)
        #expect(stored.count == 1)
        #expect(stored.first?.serverMessageId == 1)
        #expect(stored.first?.creatorServerPersonId == PID.alice)
        #expect(stored.first?.recipientServerPersonId == PID.me)
        #expect(stored.first?.content == "hi")
        #expect(stored.first?.isRead == false)
    }

    @Test
    func reimportIsIdempotentAndUpdatesIsRead() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let me = Self.person(id: PID.me, name: "me", displayName: "Me", avatar: nil)
        let alice = Self.person(id: PID.alice, name: "alice", displayName: "Alice", avatar: nil)

        let accountId = try await appDatabase.writer.write { db -> Int64 in
            try Self.seedAccount(db, keychainId: "kc-1", ownServerPersonId: PID.me).accountId
        }

        let unread = Self.view(messageId: 1, creator: alice, recipient: me, content: "hello", published: Date(timeIntervalSince1970: 1000), read: false)
        try await appDatabase.upsertPrivateMessages([unread], accountId: accountId)

        // Re-import the SAME server message, now marked read with edited content.
        let readEdited = Self.view(messageId: 1, creator: alice, recipient: me, content: "hello (edited)", published: Date(timeIntervalSince1970: 1000), read: true)
        try await appDatabase.upsertPrivateMessages([readEdited], accountId: accountId)

        let stored = appDatabase.privateMessagesSync(accountId: accountId)
        // No duplicate row for the same (accountId, serverMessageId).
        #expect(stored.count == 1)
        #expect(stored.first?.isRead == true)
        #expect(stored.first?.content == "hello (edited)")
    }

    @Test
    func reimportNeverDowngradesReadBackToUnread() async throws {
        // A message read locally (or already read server-side) must stay read
        // when a later server page re-imports it as unread. On a v4 instance the
        // per-message read is cleared only locally (the notification id needed to
        // mark it server-side isn't carried), so the server keeps reporting it
        // unread; without this monotonic guard the re-import would revert the read
        // row and the DM thread would re-mark it and double-decrement the badge.
        let appDatabase = try AppDatabase.inMemory()
        let me = Self.person(id: PID.me, name: "me", displayName: "Me", avatar: nil)
        let alice = Self.person(id: PID.alice, name: "alice", displayName: "Alice", avatar: nil)

        let accountId = try await appDatabase.writer.write { db -> Int64 in
            try Self.seedAccount(db, keychainId: "kc-1", ownServerPersonId: PID.me).accountId
        }

        let read = Self.view(messageId: 1, creator: alice, recipient: me, content: "hi", published: Date(timeIntervalSince1970: 1000), read: true)
        try await appDatabase.upsertPrivateMessages([read], accountId: accountId)

        // Server page still reports it unread (v4 never learned about the read).
        let staleUnread = Self.view(messageId: 1, creator: alice, recipient: me, content: "hi", published: Date(timeIntervalSince1970: 1000), read: false)
        try await appDatabase.upsertPrivateMessages([staleUnread], accountId: accountId)

        let stored = appDatabase.privateMessagesSync(accountId: accountId)
        #expect(stored.count == 1)
        #expect(stored.first?.isRead == true)
    }

    // MARK: - observeConversations

    @Test
    func conversationsGroupByCorrespondentWithUnreadAndOrdering() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let me = Self.person(id: PID.me, name: "me", displayName: "Me", avatar: nil)
        let alice = Self.person(id: PID.alice, name: "alice", displayName: "Alice", avatar: "https://a.test/alice.png")
        let bob = Self.person(id: PID.bob, name: "bob", displayName: "Bob", avatar: nil)

        let accountId = try await appDatabase.writer.write { db -> Int64 in
            try Self.seedAccount(db, keychainId: "kc-1", ownServerPersonId: PID.me).accountId
        }

        let t = { (s: TimeInterval) in Date(timeIntervalSince1970: s) }
        try await appDatabase.upsertPrivateMessages(
            [
                // Thread with Alice: one incoming unread + one outgoing (sent by me).
                Self.view(messageId: 1, creator: alice, recipient: me, content: "alice 1", published: t(1000), read: true),
                Self.view(messageId: 2, creator: me, recipient: alice, content: "me to alice", published: t(1100), read: true),
                Self.view(messageId: 3, creator: alice, recipient: me, content: "alice latest", published: t(1200), read: false),
                // Thread with Bob: a single incoming read message, OLDER than Alice's latest.
                Self.view(messageId: 4, creator: bob, recipient: me, content: "bob hi", published: t(900), read: true),
            ],
            accountId: accountId
        )

        let conversations = await Self.firstConversations(appDatabase.observeConversations(accountId: accountId))

        // Two correspondents (Alice, Bob); a thread is one row regardless of msg count.
        #expect(conversations.count == 2)
        // Newest-thread first: Alice (latest t=1200) before Bob (latest t=900).
        #expect(conversations.map(\.correspondentServerPersonId) == [PID.alice, PID.bob])

        let aliceRow = try #require(conversations.first)
        #expect(aliceRow.correspondentName == "Alice")
        #expect(aliceRow.correspondentAvatarUrl == "https://a.test/alice.png")
        #expect(aliceRow.latestContent == "alice latest")
        #expect(aliceRow.latestPublished == t(1200))
        // Unread = incoming-only: message 3 (from Alice) is unread; the outgoing
        // message 2 and the read message 1 do not count.
        #expect(aliceRow.unreadCount == 1)

        let bobRow = conversations[1]
        #expect(bobRow.correspondentName == "Bob")
        #expect(bobRow.latestContent == "bob hi")
        #expect(bobRow.unreadCount == 0)
    }

    @Test
    func conversationsFallBackToCreatorWhenOwnPersonUnknown() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let me = Self.person(id: PID.me, name: "me", displayName: "Me", avatar: nil)
        let alice = Self.person(id: PID.alice, name: "alice", displayName: "Alice", avatar: nil)

        // ownPersonId nil → fall back to treating the creator as the correspondent.
        let accountId = try await appDatabase.writer.write { db -> Int64 in
            try Self.seedAccount(db, keychainId: "kc-1", ownServerPersonId: nil).accountId
        }

        try await appDatabase.upsertPrivateMessages(
            [
                Self.view(messageId: 1, creator: alice, recipient: me, content: "incoming", published: Date(timeIntervalSince1970: 1000), read: false),
            ],
            accountId: accountId
        )

        let conversations = await Self.firstConversations(appDatabase.observeConversations(accountId: accountId))
        #expect(conversations.count == 1)
        // With own-person unknown the correspondent is the creator (Alice), not me.
        #expect(conversations.first?.correspondentServerPersonId == PID.alice)
        #expect(conversations.first?.unreadCount == 1)
    }

    // MARK: - observeMessages

    @Test
    func messagesReturnThreadOldestFirst() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let me = Self.person(id: PID.me, name: "me", displayName: "Me", avatar: nil)
        let alice = Self.person(id: PID.alice, name: "alice", displayName: "Alice", avatar: nil)
        let bob = Self.person(id: PID.bob, name: "bob", displayName: "Bob", avatar: nil)

        let accountId = try await appDatabase.writer.write { db -> Int64 in
            try Self.seedAccount(db, keychainId: "kc-1", ownServerPersonId: PID.me).accountId
        }

        let t = { (s: TimeInterval) in Date(timeIntervalSince1970: s) }
        try await appDatabase.upsertPrivateMessages(
            [
                // Alice thread, out of order on insert.
                Self.view(messageId: 3, creator: me, recipient: alice, content: "me reply", published: t(1200), read: true),
                Self.view(messageId: 1, creator: alice, recipient: me, content: "alice first", published: t(1000), read: true),
                Self.view(messageId: 2, creator: me, recipient: alice, content: "me middle", published: t(1100), read: true),
                // Bob thread — must NOT leak into the Alice thread.
                Self.view(messageId: 4, creator: bob, recipient: me, content: "bob noise", published: t(1050), read: true),
            ],
            accountId: accountId
        )

        let messages = await Self.firstMessages(
            appDatabase.observeMessages(accountId: accountId, correspondentServerPersonId: PID.alice)
        )

        // Only the Alice thread (3 messages), oldest first.
        #expect(messages.map(\.serverMessageId) == [1, 2, 3])
        #expect(messages.map(\.content) == ["alice first", "me middle", "me reply"])
        // Author name joined from the person table.
        #expect(messages.first?.creatorName == "Alice")
        #expect(messages.first?.creatorServerPersonId == PID.alice)
    }
}
