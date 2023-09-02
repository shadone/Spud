//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let dataStore = OSLog(subsystem: subsystem, category: "DataStore")
    static let utils = OSLog(subsystem: subsystem, category: "Utils")
}
