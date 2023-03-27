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
    private let context: NSManagedObjectContext
    private let itemID: ObjectID
    private let boardID: ObjectID

    private var dataSource: DataSource?
    private lazy var fetchedResultsController: NSFetchedResultsController<Tag> = {
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(Tag.board), boardID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.sortOrder, ascending: true)]

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)
        controller.delegate = self

        return controller
    }()

    var boardName: String {
        guard let board = try? context.existingObject(with: boardID) as? Board else {
            fatalError("#\(#function): Failed to retrieve board object by objectID")
        }

        if board.isInbox {
            return Strings.Common.inbox
        }

        return board.name ?? Strings.Common.untitledBoard
    }

    var isEditing = false

    lazy var createTagFooterTap = PassthroughSubject<Void, Never>()

    // MARK: - Lifecycle

    init(
        storageProvider: StorageProvider = .shared,
        itemID: ObjectID,
        boardID: ObjectID,
        context: NSManagedObjectContext
    ) {
        self.storageProvider = storageProvider
        self.itemID = itemID
        self.boardID = boardID
        self.context = context
    }

    // MARK: - Methods

    func configureDataSource(for collectionView: UICollectionView) {
        let cellRegistration = UICollectionView
            .CellRegistration<UICollectionViewListCell, ObjectID> { [unowned self] cell, _, tagID in
                guard
                    let tag = try? context.existingObject(with: tagID) as? Tag,
                    let item = try? context.existingObject(with: itemID) as? Item,
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
                cell.accessories = [
                    .checkmark(displayed: .whenNotEditing, options: .init(isHidden: !isSelected)),
                    .reorder(displayed: .whenEditing),
                    .delete(displayed: .whenEditing) {
                        Task {
                            await self.deleteTag(tag)
                        }
                    }
                ]
            }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [unowned self] footer, _, _ in
            var content = UIListContentConfiguration.plainFooter()
            content.text = Strings.TagSelector.create
            content.textProperties.font = .systemFont(ofSize: 18, weight: .semibold)
            content.textProperties.color = .label
            content.image = UIImage(systemName: "plus")
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)

            footer.contentConfiguration = content
            footer.backgroundConfiguration?.backgroundColor = .systemBackground
            footer.backgroundConfiguration?.visualEffect = nil
            footer.automaticallyUpdatesBackgroundConfiguration = false
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(footerTapped))
            footer.addGestureRecognizer(tapGesture)
        }

        let dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, tagID in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: tagID)
        }

        dataSource.reorderingHandlers.canReorderItem = { _ in true }
        dataSource.reorderingHandlers.didReorder = { [unowned self] transaction in
            let tagIDs = transaction.finalSnapshot.itemIdentifiers
            reorderTags(tagIDs)
        }

        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            if elementKind == UICollectionView.elementKindSectionFooter {
                return collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
            } else {
                return nil
            }
        }

        self.dataSource = dataSource
    }

    func fetchTags() {
        try? fetchedResultsController.performFetch()
    }

    func toggleTag(at indexPath: IndexPath) {
        let tag = fetchedResultsController.object(at: indexPath)

        Task {
            do {
                try await storageProvider.toggleTagging(itemID: itemID, tagID: tag.objectID)
            } catch {
                print("#\(#function): Failed to toggle tagging, \(error)")
            }
        }
    }

    func newTagViewModel() -> TagEditorViewModel {
        TagEditorViewModel(
            storageProvider: storageProvider,
            context: context,
            scenario: .create(relatedBoardID: boardID))
    }

    func editTagViewModel(at indexPath: IndexPath) -> TagEditorViewModel {
        guard
            let dataSource = dataSource,
            let tagID = dataSource.itemIdentifier(for: indexPath),
            let tag = context.object(with: tagID) as? Tag
        else { fatalError("#\(#function): Failed to retrieve tag object") }

        return TagEditorViewModel(storageProvider: storageProvider, context: context, scenario: .update(tag: tag))
    }

    // MARK: - Private

    private func deleteTag(_ tag: Tag) async {
        do {
            try await storageProvider.deleteTag(tag: tag)
            if var snapshot = dataSource?.snapshot() {
                snapshot.deleteItems([tag.objectID])
                await dataSource?.apply(snapshot, animatingDifferences: true)
            }
        } catch {
            print("#\(#function): Failed to delete tag, \(error)")
        }
    }

    private func reorderTags(_ ids: [ObjectID]) {
        Task {
            do {
                try await storageProvider.reorderTags(orderedTagIDs: ids)
            } catch {
                print("#\(#function): Failed to save reordered tags, \(error)")
            }
        }
    }

    @objc private func footerTapped() {
        createTagFooterTap.send()
    }
}

extension TagSelectorViewModel: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        guard !isEditing else { return }
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
