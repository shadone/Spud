//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let auth = OSLog(subsystem: subsystem, category: "Auth")
    static let dataStore = OSLog(subsystem: subsystem, category: "DataStore")
    static let lemmyService = OSLog(subsystem: subsystem, category: "LemmyService")
    static let lemmyDataService = OSLog(subsystem: subsystem, category: "LemmyDataService")
    static let accountService = OSLog(subsystem: subsystem, category: "AccountService")
    static let siteService = OSLog(subsystem: subsystem, category: "SiteService")
    static let schedulerService = OSLog(subsystem: subsystem, category: "SchedulerService")
    static let postContentDetectorService = OSLog(subsystem: subsystem, category: "PostContentDetectorService")
    static let alertService = OSLog(subsystem: subsystem, category: "AlertService")
}
