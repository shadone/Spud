//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit

/// Deterministic no-op `MetaCommunityServiceType` for snapshot dependency
/// containers: `refreshInstance` never resolves or writes anything, so a
/// snapshot's "About this instance" section renders exactly the seeded
/// `instanceMetaCommunity` cache rows (or stays absent when none are seeded).
/// Shared by every snapshot suite whose VC dependencies reach
/// `HasMetaCommunityService`.
struct StubMetaCommunityService: MetaCommunityServiceType {
    func refreshInstance(host _: String, siteName _: String?, forAccountKeychainId _: String) async { }
}
