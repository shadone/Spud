//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os.log

extension OSLog {
    private static var subsystem = Bundle(for: DependencyContainer.self).bundleIdentifier!

    static let topPostsProvider = OSLog(subsystem: subsystem, category: "TopPostsProvider")
}
