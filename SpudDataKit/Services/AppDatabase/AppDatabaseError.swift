//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public enum AppDatabaseError: Error {
    /// Could not resolve the App Group container URL.
    case appGroupContainerUnavailable
}
