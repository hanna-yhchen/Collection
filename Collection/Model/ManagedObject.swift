//
//  ManagedObject.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/15.
//

import CoreData

struct ManagedObject {
    enum Entity {
        case board(ObjectID)
        case item(ObjectID)

        var deletionSituation: NSManagedObjectContext.SituationForSaving {
            switch self {
            case .board:
                return .deleteBoard
            case .item:
                return .deleteItem
            }
        }
    }

    // MARK: - Properties

    let entity: Entity
    let objectID: ObjectID

    var description: String {
        switch entity {
        case .board:
            return Strings.Common.board
        case .item:
            return Strings.Common.item
        }
    }

    // MARK: - Initializer

    init(entity: Entity) {
        self.entity = entity
        switch entity {
        case .board(let objectID):
            self.objectID = objectID
        case .item(let objectID):
            self.objectID = objectID
        }
    }

    // MARK: - Methods

    func delete(context: NSManagedObjectContext) async throws {
        try await context.perform {
            let object = try context.existingObject(with: objectID)
            context.delete(object)
            try context.save(situation: entity.deletionSituation)
        }
    }
}
