//
//  StorageProvider+Item.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/11.
//

import CoreData

extension StorageProvider {
    private func addItem(
        name: String? = nil,
        displayType: DisplayType,
        uti: String,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: ObjectID,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? newTaskContext()

        try await context.perform {
            let item = Item(context: context)
            item.name = name
            item.uti = uti
            item.note = note
            item.uuid = UUID()
            item.displayType = displayType.rawValue

            let thumbnail = Thumbnail(context: context)
            thumbnail.data = thumbnailData
            thumbnail.item = item

            let itemDataObject = ItemData(context: context)
            itemDataObject.data = itemData
            itemDataObject.item = item

            let currentDate = Date()
            item.creationDate = currentDate
            item.updateDate = currentDate

            if let board = context.object(with: boardID) as? Board {
                board.addToItems(item)
            }

            try context.save(situation: .addItem)
        }
    }

    func updateItem(
        itemID: ObjectID,
        name: String? = nil,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: ObjectID? = nil,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? newTaskContext()

        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw CoreDataError.unfoundObjectInContext
        }

        try await context.perform {
            if let name = name {
                item.name = name
            }
            if let note = note {
                item.note = note
            }
            if let itemData = itemData, let itemDataObject = item.itemData {
                itemDataObject.data = itemData
            }
            if let thumbnailData = thumbnailData, let thumbnail = item.thumbnail {
                thumbnail.data = thumbnailData
            }
            if let boardID = boardID, let board = try context.existingObject(with: boardID) as? Board {
                board.addToItems(item)
                if let tags = item.tags {
                    board.addToTags(tags)
                }
            }

            let currentDate = Date()
            item.updateDate = currentDate

            try context.save(situation: .updateItem)
        }
    }

    func copyItem(
        itemID: ObjectID,
        toBoardID boardID: ObjectID,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? newTaskContext()

        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw CoreDataError.unfoundObjectInContext
        }

        try await context.perform {
            let copy = Item(context: context)
            copy.name = item.name
            copy.uti = item.uti
            copy.note = item.note
            copy.uuid = UUID()
            copy.displayType = item.displayType

            let thumbnail = Thumbnail(context: context)
            thumbnail.data = item.thumbnail?.data
            thumbnail.item = copy

            let itemDataObject = ItemData(context: context)
            itemDataObject.data = item.itemData?.data
            itemDataObject.item = copy

            let currentDate = Date()
            copy.creationDate = currentDate
            copy.updateDate = currentDate

            if let board = try context.existingObject(with: boardID) as? Board {
                board.addToItems(copy)
                if let tags = item.tags {
                    copy.addToTags(tags)
                    board.addToTags(tags)
                }
            }

            try context.save(situation: .copyItem)
        }
    }

    func deleteItem(
        itemID: ObjectID,
        context: NSManagedObjectContext
    ) async throws {
        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw CoreDataError.unfoundObjectInContext
        }

        try await context.perform {
            context.delete(item)
            try context.save(situation: .deleteItem)
        }
    }
}
