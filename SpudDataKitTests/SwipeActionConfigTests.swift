//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import XCTest

/// Pure-logic tests for the swipe-action model (``SwipeAction`` /
/// ``SwipeActionConfig``). Lives in SpudDataKitTests so it runs under the
/// SpudDataKit scheme; the model itself is in SpudUtilKit.
final class SwipeActionConfigTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Round-trip

    func test_config_encodeDecode_roundTrips() throws {
        let config = SwipeActionConfig(
            leadingPrimary: .upvote,
            leadingSecondary: .downvote,
            trailingPrimary: .reply,
            trailingSecondary: .save
        )
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(SwipeActionConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func test_allCases_roundTripIndividually() throws {
        for action in SwipeAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(SwipeAction.self, from: data)
            XCTAssertEqual(decoded, action, "round-trip failed for \(action.rawValue)")
        }
    }

    // MARK: Defaults match prior hardcoded behaviour

    func test_defaultPosts_matchesPriorBehaviour() {
        // Pre-M8 posts: upvote / downvote leading, reply / save trailing.
        let config = SwipeActionConfig.defaultPosts
        XCTAssertEqual(config.leadingPrimary, .upvote)
        XCTAssertEqual(config.leadingSecondary, .downvote)
        XCTAssertEqual(config.trailingPrimary, .reply)
        XCTAssertEqual(config.trailingSecondary, .save)
    }

    func test_defaultComments_matchesPriorBehaviour() {
        // Pre-M8 comments: upvote / downvote leading, reply / collapse trailing.
        let config = SwipeActionConfig.defaultComments
        XCTAssertEqual(config.leadingPrimary, .upvote)
        XCTAssertEqual(config.leadingSecondary, .downvote)
        XCTAssertEqual(config.trailingPrimary, .reply)
        XCTAssertEqual(config.trailingSecondary, .collapse)
    }

    func test_defaultForKind_selectsCorrectConfig() {
        XCTAssertEqual(SwipeActionConfig.default(for: .post), .defaultPosts)
        XCTAssertEqual(SwipeActionConfig.default(for: .comment), .defaultComments)
    }

    // MARK: Slot -> action resolution

    func test_actionForSlot_resolvesEverySlot() {
        let config = SwipeActionConfig(
            leadingPrimary: .upvote,
            leadingSecondary: .downvote,
            trailingPrimary: .share,
            trailingSecondary: .collapse
        )
        XCTAssertEqual(config.action(for: .leadingPrimary), .upvote)
        XCTAssertEqual(config.action(for: .leadingSecondary), .downvote)
        XCTAssertEqual(config.action(for: .trailingPrimary), .share)
        XCTAssertEqual(config.action(for: .trailingSecondary), .collapse)
    }

    func test_settingSlot_replacesOnlyThatSlot() {
        let config = SwipeActionConfig.defaultPosts
        let updated = config.setting(.share, for: .trailingPrimary)
        XCTAssertEqual(updated.trailingPrimary, .share)
        // Other slots untouched.
        XCTAssertEqual(updated.leadingPrimary, config.leadingPrimary)
        XCTAssertEqual(updated.leadingSecondary, config.leadingSecondary)
        XCTAssertEqual(updated.trailingSecondary, config.trailingSecondary)
    }

    // MARK: Validity / sanitization

    func test_collapse_isCommentOnly() {
        XCTAssertTrue(SwipeAction.collapse.isValid(for: .comment))
        XCTAssertFalse(SwipeAction.collapse.isValid(for: .post))
    }

    func test_assignableActions_excludeCollapseForPosts() {
        XCTAssertFalse(SwipeActionContentKind.post.assignableActions.contains(.collapse))
        XCTAssertTrue(SwipeActionContentKind.comment.assignableActions.contains(.collapse))
        // Both kinds always offer the common actions and .none.
        for kind in [SwipeActionContentKind.post, .comment] {
            XCTAssertTrue(kind.assignableActions.contains(.none))
            XCTAssertTrue(kind.assignableActions.contains(.upvote))
            XCTAssertTrue(kind.assignableActions.contains(.reply))
        }
    }

    func test_sanitizeForPost_demotesCollapseToNone() {
        let config = SwipeActionConfig(
            leadingPrimary: .upvote,
            leadingSecondary: .collapse, // invalid for posts
            trailingPrimary: .reply,
            trailingSecondary: .save
        )
        let sanitized = config.sanitized(for: .post)
        XCTAssertEqual(sanitized.leadingSecondary, .none)
        // Valid slots survive.
        XCTAssertEqual(sanitized.leadingPrimary, .upvote)
        XCTAssertEqual(sanitized.trailingPrimary, .reply)
        XCTAssertEqual(sanitized.trailingSecondary, .save)
    }

    func test_sanitizeForComment_keepsCollapse() {
        let config = SwipeActionConfig.defaultComments
        XCTAssertEqual(config.sanitized(for: .comment), config)
    }

    // MARK: Forgiving decode

    func test_decode_unknownAction_mapsToNone() throws {
        let json = """
            {
                "leadingPrimary": "upvote",
                "leadingSecondary": "teleport",
                "trailingPrimary": "reply",
                "trailingSecondary": "save"
            }
            """.data(using: .utf8)!
        let decoded = try decoder.decode(SwipeActionConfig.self, from: json)
        XCTAssertEqual(decoded.leadingSecondary, .none, "unknown action should decode to .none")
        XCTAssertEqual(decoded.leadingPrimary, .upvote)
    }

    func test_decode_missingSlot_mapsToNone() throws {
        let json = """
            { "leadingPrimary": "upvote" }
            """.data(using: .utf8)!
        let decoded = try decoder.decode(SwipeActionConfig.self, from: json)
        XCTAssertEqual(decoded.leadingPrimary, .upvote)
        XCTAssertEqual(decoded.leadingSecondary, .none)
        XCTAssertEqual(decoded.trailingPrimary, .none)
        XCTAssertEqual(decoded.trailingSecondary, .none)
    }
}
