//
//  StorageProvider+Item.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CoreData

extension StorageProvider {
    func addItem(
        name: String,
        contentType: String,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID boardID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) {
        context.perform {
            let item = Item(context: context)
            item.name = name
            item.contentType = contentType
            item.note = note

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
}
