//
//  ItemProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/6.
//

import Combine
import CoreData
import UIKit

final class ItemProvider: NSObject, ManagedObjectProvidable {
    typealias Object = Item

    // MARK: - Properties

    @Published var currentSnapshot: ManagedObjectSnapshot?

    var fetchedResultsController: NSFetchedResultsController<Item>

    private let context: NSManagedObjectContext

    // MARK: - Initializers

    init(predicate: NSPredicate?, context: NSManagedObjectContext) {
        self.context = context

        let fetchRequest = Item.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Item.creationDate, ascending: false)]
        fetchRequest.shouldRefreshRefetchedObjects = true

        self.fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)

        super.init()

        fetchedResultsController.delegate = self
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension ItemProvider: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var newSnapshot = snapshot as ManagedObjectSnapshot
        newSnapshot.reloadItems(idsToReload(in: newSnapshot))
        currentSnapshot = newSnapshot
    }
}
