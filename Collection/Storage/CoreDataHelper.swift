//
//  CoreDataHelper.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CloudKit
import CoreData

private let storageProvider = StorageProvider.shared

// MARK: - NSManagedObjectContext

extension NSManagedObjectContext {
    enum SituationForSaving: String {
        case addItem, updateItem, deleteItem
        case addTag, updateTag, deleteTag, toggleTagging
        case addBoard, updateBoard, deleteBoard
    }

    func save(situation: SituationForSaving) {
        if hasChanges {
            do {
                try save()
            } catch let error as NSError {
                print("\(#function): Failed to save context for \(situation.rawValue): \(error), \(error.userInfo)")
            }
        }
    }
}

// MARK: - NSManagedObject

extension NSManagedObject {
    var persistentStore: NSPersistentStore? {
        if storageProvider.sharedPersistentStore.contains(self) {
            return storageProvider.sharedPersistentStore
        } else if storageProvider.privatePersistentStore.contains(self) {
            return storageProvider.privatePersistentStore
        } else {
            print("#\(#function): Failed to specify the persistent store containing the object, \(self.entity)")
            return nil
        }
    }

    var isPrivate: Bool { persistentStore == storageProvider.privatePersistentStore }

    var isShared: Bool { persistentStore == storageProvider.sharedPersistentStore }

    var ownerName: String? {
        if isPrivate {
            return UserDefaults.username
        }

        // FIXME: failed to fetch shares owned by others at first launch
        guard
            let matchedShares = try? storageProvider.persistentContainer.fetchShares(matching: [objectID]),
            let share = matchedShares[objectID],
            let owner = share.participants.first(where: { $0.role == .owner }),
            let name = owner.userIdentity.nameComponents?.formatted()
        else { return "Unknown" }

        return name
    }
}

// MARK: - NSPersistentStore

extension NSPersistentStore {
    func contains(_ managedObject: NSManagedObject) -> Bool {
        guard let entityName = managedObject.entity.name else {
            print("#\(#function): Couldn't retrieve entity name for \(managedObject.entity)")
            return false
        }

        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "self == %@", managedObject)
        fetchRequest.affectedStores = [self]

        let context = storageProvider.newTaskContext()
        return context.performAndWait {
            guard
                let result = try? context.count(for: fetchRequest),
                result > 0
            else { return false }

            return true
        }
    }
}
