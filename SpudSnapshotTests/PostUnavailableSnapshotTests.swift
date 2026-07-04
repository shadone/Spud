//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import XCTest
@testable import Spud

final class PostUnavailableSnapshotTests: XCTestCase {
    func test_unavailable() {
        let vc = PostUnavailableViewController(reason: .unavailable)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro))
    }

    func test_removed() {
        let vc = PostUnavailableViewController(reason: .removed)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro))
    }

    func test_deleted() {
        let vc = PostUnavailableViewController(reason: .deleted)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro))
    }
}
