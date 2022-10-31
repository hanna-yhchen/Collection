//
//  StorageProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CoreData

enum StorageActor: String {
    case mainApp
}

class StorageProvider {
    // MARK: - Properties

    let actor: StorageActor

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "Collection")
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("#\(#function): Failed to load persistent stores: \(error), \(error.userInfo)")
            }

            print("=== Persistent store loaded: \(storeDescription)")
        }
        return container
    }()

    // MARK: - Initializer

    init(_ actor: StorageActor) {
        self.actor = actor
    }

    // MARK: - Methods

    func newTaskContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.transactionAuthor = actor.rawValue
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}
