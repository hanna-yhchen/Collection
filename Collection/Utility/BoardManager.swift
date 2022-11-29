//
//  BoardManager.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/17.
//

import CoreData
import Foundation

final class BoardManager {
    static let shared = BoardManager()

    // MARK: - Properties

    private let storageProvider: StorageProvider

    // MARK: - Initializers

    init(storageProvider: StorageProvider = .shared) {
        self.storageProvider = storageProvider
    }

    // MARK: - Methods

    func allBoards() async throws -> [Board] {
        let context = storageProvider.persistentContainer.viewContext

        return try await context.perform {
            let fetchRequest = Board.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Board.sortOrder, ascending: false)]
            return try context.fetch(fetchRequest) as [Board]
        }
    }
}
