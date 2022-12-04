//
//  CoreDataHelper.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CloudKit
import CoreData

private let storageProvider = StorageProvider.shared

typealias ObjectID = NSManagedObjectID

enum CoreDataError: Error {
    case unfoundObjectInContext
    case duplicateName
    case failedSaving
}

// MARK: - NSManagedObjectContext

extension NSManagedObjectContext {
    enum SituationForSaving: String {
        case addItem, updateItem, deleteItem, copyItem
        case addTag, updateTag, deleteTag, toggleTagging, reorderTags
        case addBoard, updateBoard, deleteBoard, mergeBoards
    }

    func save(situation: SituationForSaving) throws {
        if hasChanges {
            do {
                try save()
            } catch let error as NSError {
                print("#\(#function): Failed to save context for \(situation.rawValue): \(error), \(error.userInfo)")
                throw CoreDataError.failedSaving
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

    var shareRecord: CKShare? {
        guard
            let matchedShares = try? storageProvider.persistentContainer.fetchShares(matching: [objectID]),
            let shareRecord = matchedShares[objectID]
        else { return nil }

        return shareRecord
    }

    var owner: CKShare.Participant? {
        guard
            let shareRecord = shareRecord,
            let owner = shareRecord.participants.first(where: { $0.role == .owner })
        else { return nil }

        return owner
    }

    var isOwnedByCurrentUser: Bool {
        guard isShared else { return true }

        guard
            let shareRecord = shareRecord,
            let currentUser = shareRecord.currentUserParticipant
        else { return false }

        return currentUser.role == .owner
    }

    var ownerName: String {
        // FIXME: failed to fetch shares owned by others at first launch
        guard
            let owner = owner,
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

// MARK: - CKShare

extension CKShare {
    var persistentStore: NSPersistentStore? {
        let persistentContainer = storageProvider.persistentContainer
        let privatePersistentStore = storageProvider.privatePersistentStore
        if let shares = try? persistentContainer.fetchShares(in: privatePersistentStore) {
            let zoneIDs = shares.map { $0.recordID.zoneID }
            if zoneIDs.contains(recordID.zoneID) {
                return privatePersistentStore
            }
        }

        let sharedPersistentStore = storageProvider.sharedPersistentStore
        if let shares = try? persistentContainer.fetchShares(in: sharedPersistentStore) {
            let zoneIDs = shares.map { $0.recordID.zoneID }
            if zoneIDs.contains(recordID.zoneID) {
                return sharedPersistentStore
            }
        }

        return nil
    }
}

// MARK: - Default Board

extension Board {
    static let inboxBoardName = "Inbox"
}
