//
//  StorageProvider+Board.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import CoreData

extension StorageProvider {
    func addBoard(name: String) {
        // TODO: validate uniqueness
        let context = newTaskContext()
        context.perform {
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
