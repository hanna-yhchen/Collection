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
                return "Duplicate to..."
            case .move:
                return "Move to..."
            }
        }
    }

    // MARK: - Properties

    let scenario: Scenario
    @Published var boards: [Board] = []

    private let itemManager: ItemManager
    private let boardManager: BoardManager

    // MARK: - Initializers

    init(itemManager: ItemManager = .shared, boardManager: BoardManager = .shared, scenario: Scenario) {
        self.itemManager = itemManager
        self.boardManager = boardManager
        self.scenario = scenario
    }

    // MARK: - Methods

    func fetchAllBoards() {
        Task {
            do {
                let boards = try await boardManager.allBoards()
                self.boards = boards
            } catch {
                print("#\(#function): Failed to fetch all boards, \(error)")
                // TODO: error handling
            }
        }
    }

    func moveItem(to boardID: ObjectID) async throws {
        switch scenario {
        case .copy(let itemID):
            try await itemManager.copyItem(itemID: itemID, toBoardID: boardID)
        case .move(let itemID):
            try await itemManager.updateItem(itemID: itemID, boardID: boardID)
        }
    }
}
