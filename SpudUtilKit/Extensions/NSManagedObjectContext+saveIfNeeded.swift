//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log

private let logger = Logger(.dataStore)

public extension NSManagedObjectContext {
    func saveIfNeeded() {
        guard hasChanges else { return }

        do {
            try save()
        } catch {
            logger.error("Failed to save context for: \(String(describing: error), privacy: .public)")
        }
    }
}
