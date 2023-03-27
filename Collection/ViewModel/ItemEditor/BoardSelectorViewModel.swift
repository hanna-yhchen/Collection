//
//  BoardSelectorViewModel.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/17.
//

import Combine
import Foundation

final class BoardSelectorViewModel {

    enum Scenario {
        case copy(ObjectID)
        case move(ObjectID)

        var title: String {
            switch self {
            case .copy:
                return Strings.BoardSelector.Title.copy
            case .move:
                return Strings.BoardSelector.Title.move
            }
        }
    }

    // MARK: - Properties

    let scenario: Scenario
    @Published var boards: [Board] = []

    private let storageProvider: StorageProvider

    // MARK: - Initializers

    init(storageProvider: StorageProvider, scenario: Scenario) {
        self.storageProvider = storageProvider
        self.scenario = scenario

        storageProvider.mergeDuplicateInboxIfNeeded()
    }

    // MARK: - Methods

    func fetchBoards() async {
        let context = storageProvider.persistentContainer.viewContext

        do {
            let inboxBoardID = storageProvider.getInboxBoardID()
            let boards = try await context.perform {
                let fetchRequest = Board.fetchRequest()
                fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "%K != %@", #keyPath(Board.name), Board.inboxBoardName),
                    NSPredicate(format: "SELF == %@", inboxBoardID)
                ])
                fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Board.sortOrder, ascending: false)]
                return try context.fetch(fetchRequest) as [Board]
            }

            self.boards = boards
        } catch {
            print("#\(#function): Failed to fetch boards, \(error)")
        }
    }

    func moveItem(to boardID: ObjectID) async throws {
        switch scenario {
        case .copy(let itemID):
            try await storageProvider.copyItem(itemID: itemID, toBoardID: boardID)
        case .move(let itemID):
            try await storageProvider.updateItem(itemID: itemID, boardID: boardID)
        }
    }
}
