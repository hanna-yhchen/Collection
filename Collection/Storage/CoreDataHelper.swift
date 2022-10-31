//
//  CoreDataHelper.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CoreData

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
