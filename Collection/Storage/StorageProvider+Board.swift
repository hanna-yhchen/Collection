//
//  StorageProvider+Board.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import CoreData

extension StorageProvider {
    func addBoard(name: String, context: NSManagedObjectContext) {
        guard !hasExistedBoardName(name, context: context) else { return }
        // TODO: handle situation of adding existed board name
        context.performAndWait {
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

            context.save(situation: .addBoard)
        }
    }
}

extension StorageProvider {
    private func hasExistedBoardName(_ name: String, context: NSManagedObjectContext) -> Bool {
        let fetchRequest = Board.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K = %@", #keyPath(Board.name), name as String)

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
