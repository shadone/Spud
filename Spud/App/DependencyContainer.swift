//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct DependencyContainer: HasDataStore, HasAccountService, HasImageService {
    let dataStore: DataStoreType = DataStore()
    let accountService: AccountServiceType
    let imageService: ImageServiceType = ImageService()

    init() {
        accountService = AccountService(dataStore: dataStore)
        start()
    }

    private func start() {
        dataStore.startService()
    }
}
