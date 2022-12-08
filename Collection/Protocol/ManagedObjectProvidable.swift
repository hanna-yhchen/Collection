//
//  ManagedObjectProvidable.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/7.
//

import CoreData
import UIKit

protocol ManagedObjectProvidable: AnyObject {
    associatedtype Object: NSFetchRequestResult

    var currentSnapshot: ManagedObjectSnapshot? { get set }
    var fetchedResultsController: NSFetchedResultsController<Object> { get set }
}

extension ManagedObjectProvidable {
    func performFetch() {
        try? fetchedResultsController.performFetch()
    }

    func updatePredicate(_ predicate: NSPredicate) {
        let fetchRequest = fetchedResultsController.fetchRequest
        fetchRequest.predicate = predicate
        performFetch()
    }

    func updateSortDescriptors(_ sortDescriptors: [NSSortDescriptor]) {
        let fetchRequest = fetchedResultsController.fetchRequest
        fetchRequest.sortDescriptors = sortDescriptors
        performFetch()
    }

    func idsToReload(in snapshot: ManagedObjectSnapshot) -> [ObjectID] {
        snapshot.itemIdentifiers
            .filter { objectID in
                guard
                    let currentIndex = currentSnapshot?.indexOfItem(objectID),
                    let newIndex = snapshot.indexOfItem(objectID),
                    newIndex == currentIndex,
                    let existingObject = try? fetchedResultsController
                        .managedObjectContext
                        .existingObject(with: objectID)
                else { return false }

                return existingObject.isUpdated
            }
    }

    func object(with id: ObjectID) -> Object? {
        try? fetchedResultsController
            .managedObjectContext
            .existingObject(with: id) as? Object
    }
}

extension ManagedObjectProvidable where Self: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var newSnapshot = snapshot as ManagedObjectSnapshot
        newSnapshot.reloadItems(idsToReload(in: newSnapshot))
        currentSnapshot = newSnapshot
    }
}
