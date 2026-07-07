//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

/// Polls up to a generous 10s deadline until `isRendered` is true, laying the
/// cell out each turn, then fails loudly (and stops) if the terminal state
/// never arrived.
///
/// The cell drives its image load on an unstructured `@MainActor` `Task`
/// (`configure` -> `loadPostImage`). Under Swift Testing's full-target
/// parallel load, that Task competes with every other `@MainActor` async test
/// for main-actor time, so a short fixed wall-clock budget can expire before
/// it is ever scheduled — the historical flake (the give-up was silent, so
/// the caller's `#expect` misreported a timeout as a state bug). The budget
/// is therefore generous (the real render work is microseconds; it only needs
/// to be scheduled), and a genuine failure to render still surfaces as a loud
/// `Issue`, attributed to the caller's line via `sourceLocation`, mirroring
/// `PendingPostSnapshotTests`' "await until rendered, or fail loudly and
/// stop" precedent.
///
/// Shared by `PostDetailHeaderDegradedImageTests` and
/// `PostDetailHeaderImageReuseTests` — do not fork another copy of this;
/// extend it in place.
@MainActor
func waitUntilRendered(
    _ cell: PostDetailHeaderCell,
    _ description: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    isRendered: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(10)
    while !isRendered(), Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
        cell.layoutIfNeeded()
    }
    // One more turn so the terminal state's layout settles.
    await Task.yield()
    cell.layoutIfNeeded()
    if !isRendered() {
        Issue.record(
            "Header cell never rendered within 10s: \(description)",
            sourceLocation: sourceLocation
        )
        return
    }
}
