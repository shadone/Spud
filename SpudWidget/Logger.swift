//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle(for: DependencyContainer.self).bundleIdentifier!

    static let entryService = Logger(subsystem: subsystem, category: "EntryService")
    static let topPostsProvider = Logger(subsystem: subsystem, category: "TopPostsProvider")
}
