//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class PostInteractionRecordTests: XCTestCase {
    func testConvenienceInitDefaultsAreEmpty() {
        let record = PostInteractionRecord(accountId: 7, postServerId: 42)
        XCTAssertNil(record.id)
        XCTAssertEqual(record.accountId, 7)
        XCTAssertEqual(record.postServerId, 42)
        XCTAssertNil(record.titleSnapshot)
        XCTAssertNil(record.firstSeenAt)
        XCTAssertNil(record.lastSeenAt)
        XCTAssertEqual(record.seenCount, 0)
        XCTAssertNil(record.lastOpenedAt)
        XCTAssertEqual(record.openedCount, 0)
        XCTAssertNil(record.lastKnownCommentCount)
    }

    func testApplySnapshotOverwritesSnapshotFields() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 2)
        record.apply(PostInteractionSnapshot(
            titleSnapshot: "Hello",
            communityName: "tech",
            instanceHost: "lemmy.world",
            thumbnailUrl: "https://img.test/x.png",
            author: "alice"
        ))
        XCTAssertEqual(record.titleSnapshot, "Hello")
        XCTAssertEqual(record.communityName, "tech")
        XCTAssertEqual(record.instanceHost, "lemmy.world")
        XCTAssertEqual(record.thumbnailUrl, "https://img.test/x.png")
        XCTAssertEqual(record.author, "alice")
    }
}
