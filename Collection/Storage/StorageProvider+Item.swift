//
//  StorageProvider+Item.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CoreData

enum ItemError: Error {
    case unfoundItem
}

extension StorageProvider {
    // TODO: Throwable save
    func addItem(
        name: String,
        contentType: String,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) {
        context.perform {
            let item = Item(context: context)
            item.name = name
            item.contentType = contentType
            item.note = note
            item.uuid = UUID()

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

            context.save(situation: .addItem)
        }
    }

    func updateItem(
        itemID: NSManagedObjectID,
        name: String? = nil,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext
    ) async throws {
        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw ItemError.unfoundItem
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
            }

            context.save(situation: .updateItem)
        }
    }
}
