//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log

extension NSManagedObjectContext {
    func saveIfNeeded() {
        guard hasChanges else { return }

        do {
            try save()
        } catch {
            os_log("Failed to save context for: %{public}@",
                   log: .dataStore, type: .error,
                   String(describing: error))
        }
    }
}
