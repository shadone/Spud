//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct DependencyContainer: HasLemmyDataStore, HasAccountService {
    let lemmyDataStore: LemmyDataStoreType = LemmyDataStore()
    let accountService: AccountServiceType

    init() {
        accountService = AccountService(lemmyDataStore: lemmyDataStore)
        start()
    }

    private func start() {
        lemmyDataStore.startService()
    }
}
