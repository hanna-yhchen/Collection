//
//  StorageProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CoreData

class StorageProvider {
    static let shared = StorageProvider()

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
}
