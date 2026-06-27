//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import Testing

/// Pure-logic tests for the swipe-action model (``SwipeAction`` /
/// ``SwipeActionConfig``). Lives in SpudDataKitTests so it runs under the
/// SpudDataKit scheme; the model itself is in SpudUtilKit.
struct SwipeActionConfigTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Round-trip

    @Test
    func config_encodeDecode_roundTrips() throws {
        let config = SwipeActionConfig(
            leadingPrimary: .upvote,
            leadingSecondary: .downvote,
            trailingPrimary: .reply,
            trailingSecondary: .save
        )
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(SwipeActionConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test
    func allCases_roundTripIndividually() throws {
        for action in SwipeAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(SwipeAction.self, from: data)
            #expect(decoded == action, "round-trip failed for \(action.rawValue)")
        }
    }

    // MARK: Defaults match prior hardcoded behaviour

    @Test
    func defaultPosts_matchesPriorBehaviour() {
        // Pre-M8 posts: upvote / downvote leading, reply / save trailing.
        let config = SwipeActionConfig.defaultPosts
        #expect(config.leadingPrimary == .upvote)
        #expect(config.leadingSecondary == .downvote)
        #expect(config.trailingPrimary == .reply)
        #expect(config.trailingSecondary == .save)
    }

    @Test
    func defaultComments_matchesPriorBehaviour() {
        // Pre-M8 comments: upvote / downvote leading, reply / collapse trailing.
        let config = SwipeActionConfig.defaultComments
        #expect(config.leadingPrimary == .upvote)
        #expect(config.leadingSecondary == .downvote)
        #expect(config.trailingPrimary == .reply)
        #expect(config.trailingSecondary == .collapse)
    }

    @Test
    func defaultForKind_selectsCorrectConfig() {
        #expect(SwipeActionConfig.default(for: .post) == .defaultPosts)
        #expect(SwipeActionConfig.default(for: .comment) == .defaultComments)
    }

    // MARK: Slot -> action resolution

    @Test
    func actionForSlot_resolvesEverySlot() {
        let config = SwipeActionConfig(
            leadingPrimary: .upvote,
            leadingSecondary: .downvote,
            trailingPrimary: .share,
            trailingSecondary: .collapse
        )
        #expect(config.action(for: .leadingPrimary) == .upvote)
        #expect(config.action(for: .leadingSecondary) == .downvote)
        #expect(config.action(for: .trailingPrimary) == .share)
        #expect(config.action(for: .trailingSecondary) == .collapse)
    }

    @Test
    func settingSlot_replacesOnlyThatSlot() {
        let config = SwipeActionConfig.defaultPosts
        let updated = config.setting(.share, for: .trailingPrimary)
        #expect(updated.trailingPrimary == .share)
        // Other slots untouched.
        #expect(updated.leadingPrimary == config.leadingPrimary)
        #expect(updated.leadingSecondary == config.leadingSecondary)
        #expect(updated.trailingSecondary == config.trailingSecondary)
    }

    // MARK: Validity / sanitization

    @Test
    func collapse_isCommentOnly() {
        #expect(SwipeAction.collapse.isValid(for: .comment))
        #expect(!(SwipeAction.collapse.isValid(for: .post)))
    }

    @Test
    func assignableActions_excludeCollapseForPosts() {
        #expect(!(SwipeActionContentKind.post.assignableActions.contains(.collapse)))
        #expect(SwipeActionContentKind.comment.assignableActions.contains(.collapse))
        // Both kinds always offer the common actions and .none.
        for kind in [SwipeActionContentKind.post, .comment] {
            #expect(kind.assignableActions.contains(.none))
            #expect(kind.assignableActions.contains(.upvote))
            #expect(kind.assignableActions.contains(.reply))
        }
    }

    @Test
    func sanitizeForPost_demotesCollapseToNone() {
        let config = SwipeActionConfig(
            leadingPrimary: .upvote,
            leadingSecondary: .collapse, // invalid for posts
            trailingPrimary: .reply,
            trailingSecondary: .save
        )
        let sanitized = config.sanitized(for: .post)
        #expect(sanitized.leadingSecondary == .none)
        // Valid slots survive.
        #expect(sanitized.leadingPrimary == .upvote)
        #expect(sanitized.trailingPrimary == .reply)
        #expect(sanitized.trailingSecondary == .save)
    }

    @Test
    func sanitizeForComment_keepsCollapse() {
        let config = SwipeActionConfig.defaultComments
        #expect(config.sanitized(for: .comment) == config)
    }

    // MARK: Forgiving decode

    @Test
    func decode_unknownAction_mapsToNone() throws {
        let json = """
            {
                "leadingPrimary": "upvote",
                "leadingSecondary": "teleport",
                "trailingPrimary": "reply",
                "trailingSecondary": "save"
            }
            """.data(using: .utf8)!
        let decoded = try decoder.decode(SwipeActionConfig.self, from: json)
        #expect(decoded.leadingSecondary == .none, "unknown action should decode to .none")
        #expect(decoded.leadingPrimary == .upvote)
    }

    @Test
    func decode_missingSlot_mapsToNone() throws {
        let json = """
            { "leadingPrimary": "upvote" }
            """.data(using: .utf8)!
        let decoded = try decoder.decode(SwipeActionConfig.self, from: json)
        #expect(decoded.leadingPrimary == .upvote)
        #expect(decoded.leadingSecondary == .none)
        #expect(decoded.trailingPrimary == .none)
        #expect(decoded.trailingSecondary == .none)
    }
}
