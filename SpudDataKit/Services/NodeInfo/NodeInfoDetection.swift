//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Outcome of a NodeInfo probe. `.unknown` means "could not determine" —
/// NEVER "not Lemmy". Callers treat `.unknown` as fail-open.
public enum NodeInfoDetection: Sendable, Equatable {
    case known(InstanceSoftware, version: String?)
    case unknown
}
