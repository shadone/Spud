//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

/// Tests for `ActivityViewController.shouldIncludeAuthoredContent`, the pure
/// decision behind the `init`-time wiring: `init` passes `nil` for
/// `authoredSource` to `ActivityCoordinator` whenever this returns `false`, so
/// the timeline degrades to its local-only footprint (see `ActivityCoordinator`
/// - `postsEnabled`/`commentsEnabled` are both gated on `authoredSource != nil`).
///
/// This is deliberately NOT an end-to-end test through `ActivityViewController`
/// (which would need a `LemmyServiceType` actor fake - see
/// `InboxViewModelGatingTests.RecordingInboxLemmyService`, ~60 stubbed
/// requirements - just to check `authoredSource != nil`, since
/// `LemmyAuthoredActivitySource` never calls any of its methods until
/// `loadPage` is invoked). The extracted static function IS the exact condition
/// `init` branches on, so this exercises the real wiring decision without that
/// disproportionate fake.
@MainActor
struct ActivityViewControllerGatingTests {
    @Test
    func gatedInstance_excludesAuthoredContentEvenWithPersonId() {
        let gatedCapabilities = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: "1.0.0-alpha.18")
        )
        #expect(!ActivityViewController.shouldIncludeAuthoredContent(
            serverPersonId: 42,
            capabilities: gatedCapabilities
        ))
    }

    @Test
    func ungatedInstance_includesAuthoredContentWhenPersonIdResolved() {
        #expect(ActivityViewController.shouldIncludeAuthoredContent(
            serverPersonId: 42,
            capabilities: .allAvailable
        ))
    }

    @Test
    func ungatedInstance_stillExcludesAuthoredContentWithoutPersonId() {
        // Guards the pre-existing branch (no resolved person row) so this task's
        // change doesn't collapse it into "gated only".
        #expect(!ActivityViewController.shouldIncludeAuthoredContent(
            serverPersonId: nil,
            capabilities: .allAvailable
        ))
    }
}
