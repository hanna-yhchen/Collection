//
//  FetchedResultsProviding.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/8.
//

import CoreData
import UIKit

protocol FetchedResultsProviding: NSFetchedResultsControllerDelegate {
    associatedtype Object: NSManagedObject

    typealias DataSource = UICollectionViewDiffableDataSource<Int, ObjectID>
    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, ObjectID>

    var context: NSManagedObjectContext { get }
    var fetchedResultsController: NSFetchedResultsController<Object> { get set }
    var dataSource: DataSource? { get set }

    func applySnapshot(_ snapshot: Snapshot)
}

extension FetchedResultsProviding {
    func configureDataSource(
        for collectionView: UICollectionView,
        cellProvider: @escaping (UICollectionView, IndexPath, Object) -> UICollectionViewCell?
    ) {
        dataSource = DataSource(collectionView: collectionView) { [unowned self] collectionView, indexPath, objectID in
            guard let object = object(with: objectID) else {
                fatalError("#\(#function): Failed to retrieve item by objectID")
            }

            return cellProvider(collectionView, indexPath, object)
        }
    }

    func object(with id: ObjectID) -> Object? {
        try? context.existingObject(with: id) as? Object
    }

    func objectID(for indexPath: IndexPath) -> ObjectID? {
        guard let dataSource = dataSource else { return nil }
        return dataSource.itemIdentifier(for: indexPath)
    }

    func indexPath(for objectID: ObjectID) -> IndexPath? {
        guard let dataSource = dataSource else { return nil }
        return dataSource.indexPath(for: objectID)
    }

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

    func didChangeContent(with snapshot: NSDiffableDataSourceSnapshotReference) {
        var newSnapshot = snapshot as Snapshot
        newSnapshot.reloadItems(idsToReload(in: newSnapshot))
        applySnapshot(newSnapshot)
    }

    private func idsToReload(in snapshot: Snapshot) -> [ObjectID] {
        snapshot.itemIdentifiers
            .filter { objectID in
                guard
                    let currentSnapshot = dataSource?.snapshot(),
                    let currentIndex = currentSnapshot.indexOfItem(objectID),
                    let newIndex = snapshot.indexOfItem(objectID),
                    newIndex == currentIndex,
                    let existingObject = try? fetchedResultsController
                        .managedObjectContext
                        .existingObject(with: objectID)
                else { return false }

                return existingObject.isUpdated
            }
    }
}
