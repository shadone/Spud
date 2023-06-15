//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os.log

extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let app = OSLog(subsystem: subsystem, category: "App")
    static let lemmyService = OSLog(subsystem: subsystem, category: "LemmyService")
    static let accountService = OSLog(subsystem: subsystem, category: "AccountService")
}
