//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct DependencyContainer: HasLemmyDataStore {
    let lemmyDataStore: LemmyDataStoreType = LemmyDataStore()

    init() {
        start()
    }

    private func start() {
        lemmyDataStore.startService()
    }
}
