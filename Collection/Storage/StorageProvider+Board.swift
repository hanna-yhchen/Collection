//
//  StorageProvider+Board.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import CoreData

// MARK: - Board CRUD

extension StorageProvider {
    func addBoard(name: String, context: NSManagedObjectContext) {
        guard !hasExistingBoardName(name, context: context) else { return }
        // TODO: error handling
        try? context.performAndWait {
            let board = Board(context: context)
            board.name = name

            do {
                let count = try context.count(for: Board.fetchRequest())
                board.sortOrder = Double(count + 1)
            } catch let error as NSError {
                print("#\(#function): Failed to fetch count for board objects, \(error)")
            }

            let currentDate = Date()
            board.creationDate = currentDate
            board.updateDate = currentDate

            try context.save(situation: .addBoard)
        }
    }

    func updateBoard(boardID: ObjectID, name: String, context: NSManagedObjectContext? = nil) async throws {
        let context = context ?? newTaskContext()

        guard !hasExistingBoardName(name, context: context) else {
            throw CoreDataError.duplicateName
        }

        guard let board = try context.existingObject(with: boardID) as? Board else {
            throw CoreDataError.unfoundObjectInContext
        }

        try await context.perform {
            board.name = name
            try context.save(situation: .updateBoard)
        }
    }

    func deleteBoard(boardID: NSManagedObjectID, context: NSManagedObjectContext) async throws {
        guard let board = try context.existingObject(with: boardID) as? Board else {
            throw CoreDataError.unfoundObjectInContext
        }

        try await context.perform {
            context.delete(board)
            try context.save(situation: .deleteBoard)
        }
    }
}

// MARK: - Helper

extension StorageProvider {
    func getInboxBoardID() -> ObjectID {
        guard
            let url = URL(string: UserDefaults.defaultBoardURL),
            let boardID = persistentContainer.persistentStoreCoordinator
                .managedObjectID(forURIRepresentation: url)
        else { fatalError("#\(#function): Failed to retrieve default inbox board") }

        return boardID
    }

    private func hasExistingBoardName(_ name: String, context: NSManagedObjectContext) -> Bool {
        let fetchRequest = Board.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(Board.name), name as String)

        return context.performAndWait {
            do {
                let count = try context.count(for: fetchRequest)
                return count > 0 // swiftlint:disable:this empty_count
            } catch let error as NSError {
                fatalError("#\(#function): Failed to fetch count for boards with given name, \(error)")
            }
        }
    }
}
