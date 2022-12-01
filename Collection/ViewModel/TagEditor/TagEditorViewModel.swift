//
//  TagEditorViewModel.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/29.
//

import Combine
import CoreData

final class TagEditorViewModel {

    enum Scenario {
        case create(relatedBoardID: ObjectID)
        case update(tag: Tag)

        var title: String {
            switch self {
            case .create:
                return "New Tag"
            case .update:
                return "Edit Tag"
            }
        }

        var tagName: String? {
            switch self {
            case .create:
                return nil
            case .update(let tag):
                return tag.name
            }
        }

        var tagColorIndex: Int? {
            switch self {
            case .create:
                return nil
            case .update(let tag):
                return Int(tag.color)
            }
        }
    }

    // MARK: - Properties

    let scenario: Scenario

    private let storageProvider: StorageProvider
    private let context: NSManagedObjectContext

    @Published var tagName = ""
    var selectedColorIndex = 0

    private(set) lazy var canSave = $tagName
        .map { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }
        .eraseToAnyPublisher()

    // MARK: - Lifecycle

    init(storageProvider: StorageProvider, context: NSManagedObjectContext, scenario: Scenario) {
        self.storageProvider = storageProvider
        self.context = context
        self.scenario = scenario
        self.tagName = scenario.tagName ?? ""
    }

    // MARK: - Methods

    func save() async throws {
        guard let color = TagColor(rawValue: Int16(selectedColorIndex)) else { return }

        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch scenario {
        case .create(let boardID):
            do {
                try await StorageProvider.shared.addTag(name: trimmedName, color: color, boardID: boardID)
            } catch {
                print("#\(#function): Failed to add new tag, \(error)")
                throw error
            }
        case .update(let tag):
            do {
                try await StorageProvider.shared.updateTag(tag: tag, name: trimmedName, color: color)
            } catch {
                print("#\(#function): Failed to add new tag, \(error)")
                throw error
            }
        }
    }
}
