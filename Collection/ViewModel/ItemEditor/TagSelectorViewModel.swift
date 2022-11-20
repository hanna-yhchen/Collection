//
//  TagSelectorViewModel.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/18.
//

import CoreData
import Combine
import UIKit

final class TagSelectorViewModel: NSObject {

    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, ObjectID>
    typealias DataSource = UICollectionViewDiffableDataSource<Int, ObjectID>

    // MARK: - Properties

    private let storageProvider: StorageProvider
    private let itemID: ObjectID

    private var dataSource: DataSource?
    private lazy var fetchedResultsController: NSFetchedResultsController<Tag> = {
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.sortOrder, ascending: true)]

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: storageProvider.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        controller.delegate = self

        return controller
    }()

    // MARK: - Lifecycle

    init(storageProvider: StorageProvider = .shared, itemID: ObjectID) {
        self.storageProvider = storageProvider
        self.itemID = itemID
    }

    // MARK: - Methods

    func configureDataSource(for collectionView: UICollectionView) {
        let cellRegistration = UICollectionView.CellRegistration(handler: cellRegistrationHandler)

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, tagID in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: tagID)
        }
    }

    func fetchTags() {
        try? fetchedResultsController.performFetch()
    }

    func toggleTagAt(_ indexPath: IndexPath) {
        let tag = fetchedResultsController.object(at: indexPath)

        Task {
            do {
                try await storageProvider.toggleTagging(itemID: itemID, tagID: tag.objectID)
            } catch {
                print("#\(#function): Failed to toggle tagging, \(error)")
            }
        }
    }

    // MARK: - Private

    private func cellRegistrationHandler(cell: UICollectionViewListCell, indexPath: IndexPath, tagID: ObjectID) {
        guard
            let tag = try? fetchedResultsController
                .managedObjectContext
                .existingObject(with: tagID) as? Tag,
            let item = try? fetchedResultsController
                .managedObjectContext
                .existingObject(with: itemID) as? Item,
            let isSelected = item.tags?.contains(tag)
        else { fatalError("#\(#function): Failed to retrieve object by objectID") }

        var content = cell.defaultContentConfiguration()
        content.text = tag.name
        content.textProperties.font = .systemFont(ofSize: 18, weight: .semibold)
        content.image = UIImage(systemName: "tag.fill")
        content.imageProperties.tintColor = TagColor(rawValue: tag.color)?.color
        content.imageToTextPadding = 16

        cell.contentConfiguration = content
        cell.selectedBackgroundView = UIView()
        cell.accessories = [.checkmark(displayed: .always, options: .init(isHidden: !isSelected))]
    }
}

extension TagSelectorViewModel: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        guard let dataSource = dataSource else { fatalError("#\(#function): Failed to unwrap data source") }

        var newSnapshot = snapshot as Snapshot
        let currentSnapshot = dataSource.snapshot()

        let updatedIDs = newSnapshot.itemIdentifiers.filter { objectID in
            guard
                let currentIndex = currentSnapshot.indexOfItem(objectID),
                let newIndex = newSnapshot.indexOfItem(objectID),
                newIndex == currentIndex,
                let existingObject = try? controller.managedObjectContext.existingObject(with: objectID),
                existingObject.isUpdated
            else { return false }

            return true
        }
        newSnapshot.reloadItems(updatedIDs)

        dataSource.apply(newSnapshot)
    }
}
