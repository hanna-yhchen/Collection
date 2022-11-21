//
//  NoteEditorViewModel.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/9.
//

import Combine

final class NoteEditorViewModel {

    enum Scenario {
        case create(boardID: ObjectID)
        case update(item: Item)

        var title: String {
            switch self {
            case .create:
                return "New note"
            case .update:
                return "Edit note"
            }
        }
    }

    // MARK: - Properties

    private let itemManager: ItemManager
    let scenario: Scenario

    @Published var name = ""
    @Published var note = ""

    private(set) lazy var canSave = Publishers.CombineLatest($name, $note)
        .map { !($0.isEmpty && $1.isEmpty) }
        .eraseToAnyPublisher()

    var hasChanges: Bool {
        switch scenario {
        case .create:
            return !(name.isEmpty && note.isEmpty)
        case .update(let item):
            return item.name != name || item.note != note
        }
    }

    // MARK: - Initializers

    init(itemManager: ItemManager, scenario: Scenario) {
        self.itemManager = itemManager
        self.scenario = scenario

        switch scenario {
        case .update(let item):
            self.name = item.name ?? ""
            self.note = item.note ?? ""
        default:
            break
        }
    }

    // MARK: - Methods

    func save() async throws {
        // TODO: throw corresponding error msg to vc
        switch scenario {
        case .create(let boardID):
            do {
                try await itemManager.addNote(name: name, note: note, saveInto: boardID)
            } catch {
                print("#\(#function): Failed to update note item, \(error)")
            }
        case .update(let item):
            do {
                try await itemManager.updateNote(itemID: item.objectID, name: name, note: note)
            } catch {
                print("#\(#function): Failed to update note item, \(error)")
            }
        }
    }
}
