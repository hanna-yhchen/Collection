//
//  StorageProvider+Tag.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/18.
//

import CoreData

extension StorageProvider {
    func addTag(
        name: String?,
        color: TagColor,
        boardID: ObjectID,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? newTaskContext()

        try await context.perform {
            let tag = Tag(context: context)
            tag.name = name
            tag.color = color.rawValue

            let count = try context.count(for: Tag.fetchRequest())
            tag.sortOrder = Double(count + 1)

            if let board = context.object(with: boardID) as? Board {
                board.addToTags(tag)
            }

            context.save(situation: .addTag)
        }
    }

    func toggleTagging(
        itemID: ObjectID,
        tagID: ObjectID,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? newTaskContext()

        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw CoreDataError.unfoundObjectInContext
        }

        guard let tag = try context.existingObject(with: tagID) as? Tag else {
            throw CoreDataError.unfoundObjectInContext
        }

        await context.perform {
            if let tags = item.tags, tags.contains(tag) {
                item.removeFromTags(tag)
            } else {
                item.addToTags(tag)
            }
            context.save(situation: .toggleTagging)
        }
    }

    func updateTag(
        tagID: ObjectID,
        name: String?,
        color: TagColor?,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? newTaskContext()

        guard let tag = try context.existingObject(with: tagID) as? Tag else {
            throw CoreDataError.unfoundObjectInContext
        }

        await updateTag(tag: tag, name: name, color: color, context: context)
    }

    func updateTag(
        tag: Tag,
        name: String?,
        color: TagColor?,
        context: NSManagedObjectContext? = nil
    ) async {
        let context = context ?? newTaskContext()

        await context.perform {
            if let name = name {
                tag.name = name
            }

            if let color = color {
                tag.color = color.rawValue
            }

            context.save(situation: .updateTag)
        }
    }

    func deleteTag(
        tagID: ObjectID,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? newTaskContext()

        guard let tag = try context.existingObject(with: tagID) as? Tag else {
            throw CoreDataError.unfoundObjectInContext
        }

        await deleteTag(tag: tag, context: context)
    }

    func deleteTag(
        tag: Tag,
        context: NSManagedObjectContext? = nil
    ) async {
        let context = context ?? newTaskContext()

        await context.perform {
            context.delete(tag)
            context.save(situation: .deleteTag)
        }
    }
}
