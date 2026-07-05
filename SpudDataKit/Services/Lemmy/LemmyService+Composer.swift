//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.lemmyService

// MARK: - Composer outbox

/// Composer: durable drafts, optimistic post edits, and direct-message sends forwarded through the composer outbox.
public extension LemmyService {
    /// Lazily builds (and `start()`s) the per-account `ComposerOutboxService`,
    /// returning `nil` only when the account row can't be resolved. Memoized via
    /// `composerOutboxTask` so every call shares one service instance.
    private func composerOutbox() async -> ComposerOutboxService? {
        if let composerOutboxTask { return await composerOutboxTask.value }
        let task = Task<ComposerOutboxService?, Never> { [self] in
            guard let ids = try? await accountSiteIds() else { return nil }
            let performer = LemmyComposerPerformer(
                api: api,
                appDatabase: appDatabase,
                accountId: ids.0,
                siteId: ids.1
            )
            let instanceHost = await resolveInstanceHost()
            let service = ComposerOutboxService(
                accountId: ids.0,
                appDatabase: appDatabase,
                performer: performer,
                reachability: reachability,
                now: { Date().timeIntervalSince1970 },
                diagnostics: DiagnosticLog(appDatabase: appDatabase),
                instance: instanceHost
            )
            await service.start()
            return service
        }
        composerOutboxTask = task
        let result = await task.value
        if result == nil { composerOutboxTask = nil }
        return result
    }

    func saveDraft(_ input: OutboundDraftInput) async throws -> String {
        guard let ids = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(description: "account row unavailable")
        }
        return try await appDatabase.upsertOutboundDraft(input, accountId: ids.0, now: Date().timeIntervalSince1970)
    }

    func submitDraft(clientToken: String) async {
        await composerOutbox()?.submit(clientToken: clientToken)
    }

    func retryComposition(clientToken: String) async {
        await composerOutbox()?.retry(clientToken: clientToken)
    }

    func discardComposition(clientToken: String) async {
        await composerOutbox()?.discard(clientToken: clientToken)
    }

    func loadDraft(draftKey: String) async throws -> OutboundContentRecord? {
        guard let ids = try await accountSiteIds() else { return nil }
        return try await appDatabase.loadOutboundDraft(accountId: ids.0, draftKey: draftKey)
    }

    func saveDirectMessageDraft(
        body: String,
        recipientServerPersonId: Int64
    ) async throws -> String {
        guard let ids = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(description: "account row unavailable")
        }
        let input = OutboundDraftInput(
            kind: .directMessage,
            body: body,
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0,
            recipientServerPersonId: recipientServerPersonId
        )
        return try await appDatabase.upsertOutboundDraft(input, accountId: ids.0, now: Date().timeIntervalSince1970)
    }

    @discardableResult
    func sendDirectMessage(
        body: String,
        recipientServerPersonId: Int64
    ) async throws -> String {
        guard let ids = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(description: "account row unavailable")
        }
        // Create the uniquely-keyed queued row first (fast DB write). Several
        // sends to the same recipient can coexist because each row's draftKey is
        // salted with its own clientToken (see `dmSendKey`).
        let token = try await appDatabase.enqueueOutboundDirectMessage(
            body: body,
            recipientServerPersonId: recipientServerPersonId,
            accountId: ids.0,
            now: Date().timeIntervalSince1970
        )
        // `submit` enqueues then drains on a DETACHED task and returns
        // immediately; we never await the network send, so the optimistic UI
        // stays instant.
        await composerOutbox()?.submit(clientToken: token)
        return token
    }

    func applyOptimisticPostEdit(
        serverPostId: Components.Schemas.PostID,
        title: String,
        body: String?,
        url: String?,
        nsfw: Bool
    ) async {
        guard let ids = try? await accountSiteIds() else { return }
        do {
            try await appDatabase.writer.write { db in
                try OptimisticWrites.setPostContent(
                    db,
                    accountId: ids.0,
                    serverPostId: Int64(serverPostId),
                    title: title,
                    body: body,
                    url: url,
                    nsfw: nsfw
                )
            }
        } catch {
            logger.error("Optimistic post edit write failed: \(String(describing: error), privacy: .public)")
        }
    }

    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        guard let svc = await composerOutbox() else { return AsyncStream { $0.finish() } }
        return await svc.failureEvents
    }

    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        guard let svc = await composerOutbox() else { return AsyncStream { $0.finish() } }
        return await svc.successEvents
    }

    func markAsRead(
        serverPostId: Components.Schemas.PostID
    ) async throws {
        logger.debug("""
            Marking post as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.SuccessResponse
        do {
            response = try await api.markPostAsRead(postIDs: [serverPostId], read: true)
        } catch {
            logger.error("""
                Mark post as read failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Mark post as read complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public) success=\(response.success, privacy: .public)
            """)

        if response.success {
            do {
                guard let (accountRowId, _) = try await accountSiteIds() else { return }
                try await appDatabase.setPostIsRead(
                    accountId: accountRowId,
                    serverPostId: Int64(serverPostId),
                    isRead: true
                )
            } catch {
                logger.error("AppDatabase setPostIsRead failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
