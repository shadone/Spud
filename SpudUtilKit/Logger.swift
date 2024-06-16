//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let dataStore = Logger(subsystem: subsystem, category: "DataStore")
    static let utils = Logger(subsystem: subsystem, category: "Utils")
}
