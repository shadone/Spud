//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log

private let logger = Logger(.dataStore)

protocol DataStoreType: AnyObject {
    var mainContext: NSManagedObjectContext { get }
    var persistentContainer: NSPersistentContainer? { get }
    func startService()
    func newBackgroundContext() -> NSManagedObjectContext
    func saveIfNeeded()
}

protocol HasDataStore {
    var dataStore: DataStoreType { get }
}

class DataStore: DataStoreType {
    var mainContext: NSManagedObjectContext {
        guard let persistentContainer else {
            fatalError("Uninitialized persistent store")
        }
        return persistentContainer.viewContext
    }

    var storeLoadingError: Error?

    var persistentContainer: NSPersistentContainer?

    func startService() {
        guard persistentContainer == nil else {
            assertionFailure()
            return
        }

        let storeName = "DataStore"
        let storeFileName = "\(storeName).sqlite"

        let container = NSPersistentContainer(name: storeName)

        let defaultDirectoryUrl = NSPersistentContainer.defaultDirectoryURL()
        let storeUrl = defaultDirectoryUrl.appendingPathComponent(storeFileName)

        let storeDescription = NSPersistentStoreDescription(url: storeUrl)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [storeDescription]

        container.loadPersistentStores(completionHandler: { _, error in
            self.storeLoadingError = error as NSError?
        })

        if let storeLoadingError {
            logger.error("Destroying existing store due to persistent store load failure: \(String(describing: storeLoadingError), privacy: .public)")
            destroyPersistentStore(container)

            container.loadPersistentStores(completionHandler: { _, error in
                if let error = error as NSError? {
                    /*
                     Typical reasons for an error here include:
                     * The parent directory does not exist, cannot be created, or disallows writing.
                     * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                     * The device is out of space.
                     * The store could not be migrated to the current model version.
                     Check the error message to determine what the actual problem was.
                     */
                    logger.fault("Failed to load persistent store: \(String(describing: error), privacy: .public)")
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            })
        }

        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        // container.viewContext.undoManager = nil
        // container.viewContext.shouldDeleteInaccessibleFaults = true
        container.viewContext.automaticallyMergesChangesFromParent = true

        persistentContainer = container
    }

    private func destroyPersistentStore(_ container: NSPersistentContainer) {
        guard let url = container.persistentStoreDescriptions.first?.url else {
            fatalError("No store descriptions found")
        }

        do {
            try container.persistentStoreCoordinator
                .destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
        } catch {
            logger.fault("Failed to destroy persistent store: \(String(describing: error), privacy: .public)")
            fatalError("Failed to destroy persistent store: \(error)")
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        guard let persistentContainer else {
            fatalError("Uninitialized persistent store")
        }
        return persistentContainer.newBackgroundContext()
    }

    func saveIfNeeded() {
        mainContext.saveIfNeeded()
    }
}
