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
    static let resolvableVideoHost = Logger(subsystem: subsystem, category: "ResolvableVideoHost")
    static let imageService = Logger(subsystem: subsystem, category: "ImageService")
    static let alertService = Logger(subsystem: subsystem, category: "AlertService")
    static let appDatabase = Logger(subsystem: subsystem, category: "AppDatabase")
    static let explorerService = Logger(subsystem: subsystem, category: "ExplorerService")
    static let offlineDownloadService = Logger(subsystem: subsystem, category: "OfflineDownloadService")
    static let webArchive = Logger(subsystem: subsystem, category: "WebArchive")
    static let outbox = Logger(subsystem: subsystem, category: "Outbox")
    static let composerOutbox = Logger(subsystem: subsystem, category: "ComposerOutbox")
    static let inbox = Logger(subsystem: subsystem, category: "Inbox")
    static let spotlight = Logger(subsystem: subsystem, category: "Spotlight")
    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
}
