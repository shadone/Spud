//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import OSLog

private let logger = Logger(.dataStore)

public protocol DataStoreType: AnyObject {
    var mainContext: NSManagedObjectContext { get }

    func startService()
    func newBackgroundContext() -> NSManagedObjectContext
    func saveIfNeeded()

    var sizeInBytes: UInt64 { get }
    var storeUrl: URL { get }

    /// Deletes the persistent container from disk as if the app starts fresh.
    ///
    /// - Note: For tests only!
    func destroyPersistentStore()
}

public protocol HasDataStore {
    var dataStore: DataStoreType { get }
}

public class DataStore: DataStoreType {
    public var mainContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    var storeLoadingError: Error?

    let sharedContainerURL: URL = {
        let appGroupIdentifier = "group.info.ddenis.Spud.shared"
        guard
            let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            preconditionFailure("Expected a valid app group container")
        }
        return url
    }()

    public let storeUrl: URL

    public let persistentContainer: NSPersistentContainer

    public var sizeInBytes: UInt64 {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: storeUrl.path)
        else {
            return 0
        }
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }

    public init() {
        let storeName = "DataStore"
        let storeFileName = "\(storeName).sqlite"

        let bundle = Bundle(for: DataStore.self)
        guard
            let modelUrl = bundle.url(forResource: storeName, withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: modelUrl)
        else {
            fatalError("Failed to load mom")
        }

        persistentContainer = NSPersistentContainer(
            name: storeName,
            managedObjectModel: model
        )

        storeUrl = sharedContainerURL.appendingPathComponent(storeFileName)

        let storeDescription = NSPersistentStoreDescription(url: storeUrl)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        persistentContainer.persistentStoreDescriptions = [storeDescription]
    }

    public func startService() {
        persistentContainer.loadPersistentStores(completionHandler: { _, error in
            self.storeLoadingError = error as NSError?
        })

        if let storeLoadingError {
            logger.error("Destroying existing store due to persistent store load failure: \(String(describing: storeLoadingError), privacy: .public)")
            destroyPersistentStore()

            // TODO: we should pause the app while persistent container is loading.
            // e.g. show a blocking loading screen.

            persistentContainer.loadPersistentStores(completionHandler: { _, error in
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

        persistentContainer.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        // persistentContainer.viewContext.undoManager = nil
        // persistentContainer.viewContext.shouldDeleteInaccessibleFaults = true
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true

        persistentContainer.viewContext.name = "main"
    }

    public func destroyPersistentStore() {
        guard let url = persistentContainer.persistentStoreDescriptions.first?.url else {
            fatalError("No store descriptions found")
        }

        do {
            try persistentContainer.persistentStoreCoordinator
                .destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
        } catch {
            logger.fault("Failed to destroy persistent store: \(String(describing: error), privacy: .public)")
            fatalError("Failed to destroy persistent store: \(error)")
        }
    }

    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.name = "background"
        return context
    }

    public func saveIfNeeded() {
        mainContext.saveIfNeeded()
    }
}
