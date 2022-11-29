//
//  NewTagViewModel.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/29.
//

import Combine
import CoreData

final class NewTagViewModel {

    private let storageProvider: StorageProvider
    private let context: NSManagedObjectContext
    private let boardID: ObjectID

    @Published var tagName = ""
    var selectedColorIndex = 0

    private(set) lazy var canCreate = $tagName
        .map { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }
        .eraseToAnyPublisher()

    init(storageProvider: StorageProvider, context: NSManagedObjectContext, boardID: ObjectID) {
        self.storageProvider = storageProvider
        self.context = context
        self.boardID = boardID
    }

    func create() async throws {
        guard let color = TagColor(rawValue: Int16(selectedColorIndex)) else { return }

        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await StorageProvider.shared.addTag(name: trimmed, color: color, boardID: boardID)
        } catch {
            print("#\(#function): Failed to add new tag, \(error)")
            throw error
        }
    }
}
