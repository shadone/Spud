//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let auth = Logger(subsystem: subsystem, category: "Auth")
    static let lemmyService = Logger(subsystem: subsystem, category: "LemmyService")
    static let accountService = Logger(subsystem: subsystem, category: "AccountService")
    static let siteService = Logger(subsystem: subsystem, category: "SiteService")
    static let schedulerService = Logger(subsystem: subsystem, category: "SchedulerService")
    static let postContentDetectorService = Logger(subsystem: subsystem, category: "PostContentDetectorService")
    static let alertService = Logger(subsystem: subsystem, category: "AlertService")
    static let appDatabase = Logger(subsystem: subsystem, category: "AppDatabase")
    static let explorerService = Logger(subsystem: subsystem, category: "ExplorerService")
}
