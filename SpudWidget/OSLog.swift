//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

extension OSLog {
    private static var subsystem = Bundle(for: DependencyContainer.self).bundleIdentifier!

    static let entryService = OSLog(subsystem: subsystem, category: "EntryService")
    static let topPostsProvider = OSLog(subsystem: subsystem, category: "TopPostsProvider")
}
