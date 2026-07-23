//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Upserts a single comment row tied to its post. Used by vote/edit flows
    /// where we receive a fresh CommentView for one comment without rebuilding
    /// the whole tree. Skips silently if the post is not yet in AppDatabase.
    ///
    /// When `respectsPendingOutbox` is `true` (the default), any pending
    /// outbox operations for this comment will prevent the corresponding
    /// optimistic fields from being overwritten by server data.
    func upsertComment(
        from view: Lemmy.CommentView,
        accountId: Int64,
        siteId: Int64,
        respectsPendingOutbox: Bool = true
    ) async throws {
        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == Int64(view.post.id))
                .fetchOne(db)?
                .id
            else { return }

            _ = try Self.upsertComment(
                from: view,
                accountId: accountId,
                postRowId: postRowId,
                siteId: siteId,
                respectsPendingOutbox: respectsPendingOutbox,
                in: db
            )
        }
    }

    /// Reconciles the comment tree for a (post, sortType) pair with the given
    /// CommentViews, in place. Comments with missing children get an extra
    /// "load more" placeholder element.
    ///
    /// This RECONCILES existing `CommentElementRecord` rows rather than
    /// deleting and reinserting them. `CommentElementRecord.id` is an
    /// auto-increment rowid that the post-detail diffable snapshot keys on
    /// (`Item.comment(elementId:)`), and `PostDetailViewModel` intersects its
    /// collapse set against the surviving ids on every reload — so an import
    /// that minted fresh ids on every call (including every pull-to-refresh)
    /// silently discarded the reader's collapse state and churned every row
    /// identity. Real rows are matched by their local comment row id (stable:
    /// comment rows are upserted, never deleted here); "load more" placeholder
    /// rows are matched by `moreParentId`, a server comment id, which is
    /// already the semantic key `spliceMoreComments` looks them up by. There is
    /// no unique index on `(postId, sortType, position)`, so rewriting
    /// positions/depths of matched rows in place is safe; only rows whose
    /// comment left the tree are deleted.
    ///
    /// Skips the operation if the post is not yet in AppDatabase — the next
    /// `fetchFeed` or `fetchPostInfo` will land it first.
    ///
    /// - Parameter pruningAbsentElements: When `true` (the default), `comments`
    ///   is treated as the FULL desired state for `(postId, sortType)`:
    ///   positions are recomputed from a fresh `sort(comments:)` over the
    ///   whole given set, and any existing element row whose comment is
    ///   absent from it is deleted. When `false`, this call is ADDITIVE: it
    ///   only upserts rows for the comments it was given and never deletes
    ///   anything. A row that already exists (matched by its local comment
    ///   row id, or by `moreParentId` for a placeholder) keeps its stored
    ///   `position` untouched — only its other fields (depth, and for
    ///   placeholders the child count) are refreshed. A genuinely new row is
    ///   appended after the current maximum position, since its true
    ///   position relative to rows outside this call's subset can't be known
    ///   from a partial set. Preserving matched rows' positions is what keeps
    ///   a mid-walk import from visibly reshuffling the whole on-screen tree
    ///   (see `LemmyService.fetchComments`'s doc): the position would
    ///   otherwise jump to the tail on every additive import that re-touches
    ///   an already-stored row, only to self-heal once the walk's final
    ///   pruning import restores 0..N — a live `ValueObservation` reader
    ///   would watch that reshuffle happen for the whole walk.
    ///
    ///   This exists for `LemmyService.fetchComments`'s mid-walk imports: with
    ///   pruning always on, the FIRST page of any re-walk (pull-to-refresh,
    ///   the composer-success refresh, "Load more comments") pruned the
    ///   stored tree down to just that one page before the rest of the walk
    ///   regrew it — visibly truncating the on-screen tree, and, because the
    ///   pruned rows were DELETED, minting fresh element ids for every later
    ///   page on re-import (silently dropping the reader's collapse state and
    ///   scroll position). Passing `false` for every mid-walk import and
    ///   reconciling with pruning back on exactly once, after the walk's last
    ///   page (success OR failure), keeps the tree additive while it grows
    ///   and still authoritative once the walk is done — see the doc on
    ///   `LemmyService.fetchComments`.
    func upsertComments(
        forServerPostId serverPostId: Int64,
        accountId: Int64,
        siteId: Int64,
        sortType: Lemmy.CommentSortType,
        comments: [Lemmy.CommentView],
        pruningAbsentElements: Bool = true
    ) async throws {
        // An additive call with nothing to add is a genuine no-op (it has no
        // license to delete anything it wasn't given). A PRUNING call with an
        // empty set is different: `comments` being empty because the server's
        // tree really did go empty is exactly the state the final call must
        // reconcile to, so it falls through and deletes every stored element
        // below instead of leaving the stale tree behind.
        guard !comments.isEmpty || pruningAbsentElements else { return }

        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)?
                .id
            else {
                logger.debug("Skipping comment mirror - post \(serverPostId, privacy: .public) not yet in AppDatabase")
                return
            }

            let sortTypeRaw = sortType.rawValue

            // Reconcile the element rows rather than rebuilding them. The
            // post-detail diffable snapshot keys on `CommentElementRecord.id`
            // and the view model intersects its collapse set against the
            // surviving ids, so minting fresh ids on every import would silently
            // drop the reader's collapse state and churn every row identity.
            // Real rows are keyed by their local comment row id; "load more"
            // placeholders by `moreParentId` (a server comment id), which is
            // already the semantic key `spliceMoreComments` looks them up by.
            let existingElements = try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == sortTypeRaw)
                .fetchAll(db)

            var elementByCommentRowId: [Int64: CommentElementRecord] = [:]
            var elementByMoreParentId: [Int64: CommentElementRecord] = [:]
            for element in existingElements {
                if let commentId = element.commentId {
                    elementByCommentRowId[commentId] = element
                } else if let moreParentId = element.moreParentId {
                    elementByMoreParentId[moreParentId] = element
                }
            }

            let commentsWithMissingChildren: Set<Lemmy.CommentID> = Set(
                LemmyCommentImportHelper
                    .findCommentsWithMissingChildren(comments)
                    .map { Lemmy.CommentID($0.comment.id) }
            )

            let ordered = LemmyCommentImportHelper.sort(comments: comments)

            var survivingElementIds: Set<Int64> = []
            // An authoritative (pruning) import recomputes the FULL ordered
            // sequence from scratch. An additive import only ever adds rows
            // for the comments it was given, so a new row is appended after
            // the current maximum rather than the sequence restarting at 0 —
            // restarting it would stomp the positions of the untouched rows
            // this call doesn't even know about (see the doc on
            // `pruningAbsentElements`).
            var elementPosition: Int64 = pruningAbsentElements
                ? 0
                : (existingElements.map(\.position).max().map { $0 + 1 } ?? 0)
            for view in ordered {
                let path = CommentPath(path: view.comment.path)
                let depth = Int64(path.depth)

                let commentRowId = try Self.upsertComment(
                    from: view,
                    accountId: accountId,
                    postRowId: postRowId,
                    siteId: siteId,
                    respectsPendingOutbox: true,
                    in: db
                )

                // A matched row (this comment already has a stored element)
                // keeps its existing `position` in an additive import — only a
                // genuinely new row is placed at the tail. Reassigning every
                // matched row's position to the tail on every mid-walk import
                // would visibly reshuffle the whole on-screen tree for the
                // duration of the walk (see the doc on `pruningAbsentElements`
                // above); a pruning import always recomputes positions from
                // the full ordered sequence, so it keeps assigning
                // `elementPosition` to every row regardless of whether it
                // matched.
                let existingElement = elementByCommentRowId[commentRowId]
                let isNewElement = existingElement == nil
                var element = existingElement ?? CommentElementRecord(
                    postId: postRowId,
                    commentId: commentRowId,
                    position: elementPosition,
                    depth: depth,
                    sortType: sortTypeRaw
                )
                if pruningAbsentElements || isNewElement {
                    element.position = elementPosition
                }
                element.depth = depth
                // A row that was a comment stays a comment; clear any stale
                // placeholder fields defensively.
                element.moreChildCount = nil
                element.moreParentId = nil
                try element.save(db)
                if let id = element.id { survivingElementIds.insert(id) }
                if pruningAbsentElements || isNewElement { elementPosition += 1 }

                if commentsWithMissingChildren.contains(Lemmy.CommentID(view.comment.id)) {
                    let moreParentId = Int64(view.comment.id)
                    let existingPlaceholder = elementByMoreParentId[moreParentId]
                    let isNewPlaceholder = existingPlaceholder == nil
                    var placeholder = existingPlaceholder ?? CommentElementRecord(
                        postId: postRowId,
                        commentId: nil,
                        position: elementPosition,
                        depth: depth + 1,
                        sortType: sortTypeRaw,
                        moreChildCount: view.comment.childCount,
                        moreParentId: moreParentId
                    )
                    if pruningAbsentElements || isNewPlaceholder {
                        placeholder.position = elementPosition
                    }
                    placeholder.commentId = nil
                    placeholder.depth = depth + 1
                    placeholder.moreChildCount = view.comment.childCount
                    placeholder.moreParentId = moreParentId
                    try placeholder.save(db)
                    if let id = placeholder.id { survivingElementIds.insert(id) }
                    if pruningAbsentElements || isNewPlaceholder { elementPosition += 1 }
                }
            }

            // Delete only the rows that left the tree. Skipped entirely for an
            // additive import — it only knows about a subset of the tree, so
            // anything it didn't touch must be left alone, not deleted.
            if pruningAbsentElements {
                try CommentElementRecord
                    .filter(Column("postId") == postRowId)
                    .filter(Column("sortType") == sortTypeRaw)
                    .filter(!survivingElementIds.contains(Column("id")))
                    .deleteAll(db)
            }
        }
    }

    /// Splices a freshly-fetched comment SUBTREE (a "load more replies" parent and its
    /// descendants) into the existing stored comment tree for `(post, sortType)`, in place —
    /// WITHOUT the destructive whole-tree rebuild `upsertComments` performs.
    ///
    /// Locates the "load more" placeholder element for `parentServerId`, upserts the fetched
    /// comments, inserts element rows for the descendants at the placeholder's position (shifting
    /// the rows after it), removes the placeholder, and regenerates frontier "load more"
    /// placeholders for any still-missing deeper leaves (same `childCount`-driven rule as
    /// `upsertComments`).
    ///
    /// Idempotent: a no-op if the placeholder is already gone (a double tap, or a re-splice after
    /// the observation already updated the tree). Skips silently if the post is not yet mirrored.
    ///
    /// - Parameters:
    ///   - parentServerId: the server comment id of the parent whose replies were fetched.
    ///   - comments: the fetched subtree (may include the parent itself; it is not re-inserted as a
    ///     new element, only refreshed).
    func spliceMoreComments(
        forServerPostId serverPostId: Int64,
        accountId: Int64,
        siteId: Int64,
        sortType: Lemmy.CommentSortType,
        parentServerId: Int64,
        comments: [Lemmy.CommentView]
    ) async throws {
        guard !comments.isEmpty else { return }

        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)?
                .id
            else {
                logger.debug("Skipping splice - post \(serverPostId, privacy: .public) not yet in AppDatabase")
                return
            }

            let sortTypeRaw = sortType.rawValue

            // Locate the placeholder for this parent. Absent => already loaded; no-op (idempotent).
            guard
                let placeholder = try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == sortTypeRaw)
                .filter(Column("commentId") == nil)
                .filter(Column("moreParentId") == parentServerId)
                .fetchOne(db)
            else {
                return
            }
            let placeholderPosition = placeholder.position

            // Thread the fetched subtree in flat (pre-order) display order, rooted at the parent —
            // NOT via LemmyCommentImportHelper.sort, which only threads a root-anchored full tree and
            // would drop the whole subtree when `parentServerId` is a nested comment (its own
            // ancestors aren't in the fetched set). Group children by parent id (preserving the
            // server's within-parent order) and walk descendants of `parentServerId`. This skips the
            // parent itself (it already has an element) and is robust to nested parents and to a
            // child appearing before its parent in the response.
            var childrenByParent: [Int64: [Lemmy.CommentView]] = [:]
            for view in comments {
                if let parentId = CommentPath(path: view.comment.path).parent {
                    childrenByParent[Int64(parentId), default: []].append(view)
                }
            }
            var descendants: [Lemmy.CommentView] = []
            var visited: Set<Int64> = [parentServerId]
            func appendSubtree(of parentId: Int64) {
                for child in childrenByParent[parentId] ?? [] {
                    let childId = Int64(child.comment.id)
                    guard visited.insert(childId).inserted else { continue }
                    descendants.append(child)
                    appendSubtree(of: childId)
                }
            }
            appendSubtree(of: parentServerId)

            let missingChildren: Set<Lemmy.CommentID> = Set(
                LemmyCommentImportHelper
                    .findCommentsWithMissingChildren(comments)
                    .map { Lemmy.CommentID($0.comment.id) }
            )

            // Refresh the parent's own row (childCount etc.) if it was echoed in the response.
            if let parentView = comments.first(where: { Int64($0.comment.id) == parentServerId }) {
                _ = try Self.upsertComment(
                    from: parentView, accountId: accountId, postRowId: postRowId, siteId: siteId,
                    respectsPendingOutbox: true, in: db
                )
            }

            // Build the new element rows (each descendant, plus a frontier placeholder after any
            // descendant that still claims missing children), using absolute path depth.
            struct PendingElement {
                let commentId: Int64?
                let depth: Int64
                let moreChildCount: Int64?
                let moreParentId: Int64?
            }
            var pending: [PendingElement] = []
            for view in descendants {
                let depth = Int64(CommentPath(path: view.comment.path).depth)
                let commentRowId = try Self.upsertComment(
                    from: view, accountId: accountId, postRowId: postRowId, siteId: siteId,
                    respectsPendingOutbox: true, in: db
                )
                pending.append(PendingElement(commentId: commentRowId, depth: depth, moreChildCount: nil, moreParentId: nil))
                if missingChildren.contains(Lemmy.CommentID(view.comment.id)) {
                    pending.append(PendingElement(
                        commentId: nil,
                        depth: depth + 1,
                        moreChildCount: view.comment.childCount,
                        moreParentId: Int64(view.comment.id)
                    ))
                }
            }

            // Shift the rows after the placeholder to make room. The single placeholder is removed
            // and `count` new rows take positions [placeholderPosition ..< placeholderPosition + count],
            // so rows after it move by (count - 1). (count == 1 => no shift; count == 0 => -1, closing
            // the placeholder's gap.)
            let count = Int64(pending.count)
            if count != 1 {
                try db.execute(
                    sql: "UPDATE commentElement SET position = position + ? WHERE postId = ? AND sortType = ? AND position > ?",
                    arguments: [count - 1, postRowId, sortTypeRaw, placeholderPosition]
                )
            }

            try placeholder.delete(db)

            var position = placeholderPosition
            for element in pending {
                var record = CommentElementRecord(
                    postId: postRowId,
                    commentId: element.commentId,
                    position: position,
                    depth: element.depth,
                    sortType: sortTypeRaw,
                    moreChildCount: element.moreChildCount,
                    moreParentId: element.moreParentId
                )
                try record.insert(db)
                position += 1
            }
        }
    }

    /// Sets the moderator removal reason (mirrored from the public modlog) on
    /// the comments identified by their server comment id, under
    /// `(accountId, serverPostId)`. Skips silently if the post is not mirrored.
    func mirrorCommentRemovalReasons(
        forServerPostId serverPostId: Int64,
        accountId: Int64,
        reasonsByServerCommentId: [Int64: String]
    ) async throws {
        guard !reasonsByServerCommentId.isEmpty else { return }

        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)?
                .id
            else { return }

            for (serverCommentId, reason) in reasonsByServerCommentId {
                try db.execute(
                    sql: "UPDATE comment SET removedReason = ? WHERE postId = ? AND localCommentId = ?",
                    arguments: [reason, postRowId, serverCommentId]
                )
            }
        }
    }

    private static func upsertComment(
        from view: Lemmy.CommentView,
        accountId: Int64,
        postRowId: Int64,
        siteId: Int64,
        respectsPendingOutbox: Bool,
        in db: Database
    ) throws -> Int64 {
        let creatorId = try AppDatabase.upsertPerson(
            from: view.creator,
            siteId: siteId,
            in: db
        )
        // The neutral bare `Person` carries no site-ban (v4 moved `banned` onto the
        // views), but v4's `CommentView` exposes the creator's instance-wide ban as
        // `creatorBanned`. Mirror it onto the creator's person row so the comment
        // author-status SUSPENDED indicator lights up from a comment-tree import —
        // matching v3, where the bare `Person.banned` set this — instead of only after a
        // separate `PersonView` (profile) import. `PostDetailCommentRow` reads
        // `isCreatorSiteBanned` from the joined `person.isBanned` (mirrors PostImporter).
        // Coupling caveat: `isBanned` is now derived from the view's `creatorBanned` (the
        // neutral bare `Person` no longer carries the site-ban), so a locally-synthesized
        // `CommentView` that defaults `creatorBanned` to `false` would clear a real ban.
        if var creatorRecord = try PersonRecord.fetchOne(db, key: creatorId) {
            creatorRecord.isBanned = view.creatorBanned
            try creatorRecord.update(db)
        }

        let now = Date()
        let serverCommentId = Int64(view.comment.id)

        if var existing = try CommentRecord
            .filter(Column("postId") == postRowId)
            .filter(Column("localCommentId") == serverCommentId)
            .fetchOne(db)
        {
            let pendingKinds = respectsPendingOutbox
                ? try AppDatabase.pendingOutboxKinds(db, accountId: accountId, entityType: "comment", entityServerId: serverCommentId)
                : []
            let preserved = existing
            existing.creatorId = creatorId
            apply(view: view, to: &existing, now: now)
            if pendingKinds.contains(.vote) {
                existing.voteStatus = preserved.voteStatus
                existing.score = preserved.score
                existing.numberOfUpvotes = preserved.numberOfUpvotes
                existing.numberOfDownvotes = preserved.numberOfDownvotes
            }
            if pendingKinds.contains(.save) { existing.isSaved = preserved.isSaved }
            if pendingKinds.contains(.delete) { existing.isDeleted = preserved.isDeleted }
            try existing.update(db)
            return existing.id!
        }

        var record = CommentRecord(
            postId: postRowId,
            creatorId: creatorId,
            localCommentId: serverCommentId,
            body: view.comment.content,
            published: view.comment.publishedAt,
            createdAt: now,
            updatedAt: now
        )
        apply(view: view, to: &record, now: now)
        try record.insert(db)
        return record.id!
    }

    private static func apply(
        view: Lemmy.CommentView,
        to record: inout CommentRecord,
        now: Date
    ) {
        record.body = view.comment.content
        record.originalCommentUrl = view.comment.apId
        // Same source Phase-1 already read to size the "load more" placeholder
        // (`moreChildCount: view.comment.childCount` in `upsertComments` above) -
        // now also persisted on the comment row itself so a subtree reminder can
        // read/poll it without rebuilding the whole tree (`commentChildCountSync`).
        record.childCount = view.comment.childCount
        record.published = view.comment.publishedAt

        record.score = view.comment.score
        record.numberOfUpvotes = view.comment.upvotes
        record.numberOfDownvotes = view.comment.downvotes
        record.isSaved = view.isSaved

        record.isRemoved = view.comment.removed
        record.isDistinguished = view.comment.distinguished
        record.isDeleted = view.comment.deleted

        record.isCreatorModerator = view.creatorIsModerator
        record.isCreatorAdmin = view.creatorIsAdmin
        record.isCreatorBannedFromCommunity = view.creatorBannedFromCommunity
        record.isCreatorBlocked = view.isCreatorBlocked

        // Map the neutral `VoteDirection` onto the record's stored encoding
        // (1 = upvote, 0 = downvote, nil = no vote).
        switch view.myVote {
        case .up: record.voteStatus = 1
        case .down: record.voteStatus = 0
        case .none: record.voteStatus = nil
        }

        record.updatedAt = now
    }
}
