//
//  ItemListViewModel.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/7.
//

import Combine
import CoreData
import UIKit

final class ItemListViewModel: NSObject, FetchedResultsProviding {

    enum Scope {
        case allItems
        case board(ObjectID)

        var predicate: NSPredicate? {
            switch self {
            case .allItems:
                return nil
            case .board(let boardID):
                return NSPredicate(format: "%K == %@", #keyPath(Item.board), boardID)
            }
        }
    }

    enum SnapshotStrategy {
        case normal
        case reload
    }

    // MARK: - Properties

    private(set) var currentLayout: ItemLayout

    var currentMenu: AnyPublisher<UIMenu?, Never> {
        menuProvider.$currentMenu
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    lazy var switchLayout = PassthroughSubject<ItemLayout, Never>()
    lazy var shouldDisplayPlaceholder = PassthroughSubject<Bool, Never>()

    let scope: Scope
    let boardID: ObjectID
    let title: String?

    private let storageProvider: StorageProvider
    private let menuProvider: OptionMenuProvider

    let context: NSManagedObjectContext
    lazy var fetchedResultsController: NSFetchedResultsController<Item> = {
        let fetchRequest = Item.fetchRequest()
        fetchRequest.predicate = scope.predicate
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Item.creationDate, ascending: false)]
        fetchRequest.shouldRefreshRefetchedObjects = true

        return NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)
    }()

    var dataSource: DataSource?
    private var snapshotStrategy: SnapshotStrategy

    private var subscriptions = CancellableSet()

    // MARK: - Initializers

    init(
        scope: Scope,
        storageProvider: StorageProvider,
        menuProvider: OptionMenuProvider
    ) {
        self.scope = scope
        self.storageProvider = storageProvider
        self.context = storageProvider.persistentContainer.viewContext
        self.menuProvider = menuProvider
        self.snapshotStrategy = .normal
        self.currentLayout = .initialLayout

        switch scope {
        case .allItems:
            self.boardID = storageProvider.getInboxBoardID()
            self.title = "All Items"
        case .board(let boardID):
            self.boardID = boardID
            let board = try? context.existingObject(with: boardID) as? Board
            self.title = board?.name
        }

        super.init()

        fetchedResultsController.delegate = self
        addBindings()
    }

    // MARK: - Methods

    func reconfigureItems(_ items: [NSManagedObjectID]) {
        guard let dataSource = dataSource else { return }

        var newSnapshot = dataSource.snapshot()
        newSnapshot.reconfigureItems(items)

        dataSource.apply(newSnapshot)
    }

    func temporaryFileURL(of item: Item) throws -> URL {
        guard
            let data = item.itemData?.data,
            let uuid = item.uuid,
            let itemType = item.utType,
            let filenameExtension = itemType.preferredFilenameExtension
        else {
            throw ItemListError.missingFileInformation
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(uuid.uuidString)
            .appendingPathExtension(filenameExtension)

        var writingError: Error?
        var coordinatingError: NSError?

        NSFileCoordinator().coordinate(writingItemAt: fileURL, error: &coordinatingError) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writingError = error
            }
        }

        guard writingError == nil && coordinatingError == nil else {
            throw ItemListError.failedWritingToTempFile
        }

        return fileURL
    }

    func linkURL(of item: Item) throws -> URL {
        guard
            let data = item.itemData?.data,
            let url = URL(dataRepresentation: data, relativeTo: nil)
        else {
            throw ItemListError.missingFileInformation
        }

        return url
    }

    func applySnapshot(_ snapshot: Snapshot) {
        guard let dataSource = dataSource else { return }
        var newSnapshot = snapshot
        if snapshotStrategy == .reload {
            newSnapshot.reloadItems(snapshot.itemIdentifiers)
        }

        dataSource.apply(newSnapshot)
        shouldDisplayPlaceholder.send(newSnapshot.numberOfItems == 0 ? true : false)

        snapshotStrategy = .normal
    }

    // MARK: - Private

    private func addBindings() {
        storageProvider.historyManager.storeDidChangePublisher
            .map { [weak self] transactions -> [NSPersistentHistoryTransaction] in
                guard let self = self else { return [] }
                let itemEntityName = Item.entity().name

                return transactions.filter { transaction in
                    if let changes = transaction.changes {
                        switch self.scope {
                        case .allItems:
                            return changes.contains { $0.changedObjectID.entity.name == itemEntityName }
                        case .board(let boardID):
                            return changes.contains { $0.changedObjectID == boardID }
                        }
                    }
                    return false
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transactions in
                guard let self = self, !transactions.isEmpty else { return }

                self.storageProvider.mergeTransactions(
                    transactions,
                    to: self.context)
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .tagObjectDidChange, object: storageProvider)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.snapshotStrategy = .reload
                self.performFetch()
            }
            .store(in: &subscriptions)

        menuProvider.$currentSort
            .dropFirst(1)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] sort in
                switchSort(sort)
            }
            .store(in: &subscriptions)

        menuProvider.currentFilter
            .dropFirst(1)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] type, tagIDs in
                applyFilter(type: type, tagIDs: tagIDs)
            }
            .store(in: &subscriptions)

        menuProvider.$currentLayout
            .dropFirst(1)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] layout in
                currentLayout = layout
                switchLayout(layout)
            }
            .store(in: &subscriptions)
    }

    private func switchSort(_ sort: ItemSort) {
        snapshotStrategy = .reload
        updateSortDescriptors([sort.sortDescriptor])
    }

    private func applyFilter(type: DisplayType?, tagIDs: [ObjectID]) {
        snapshotStrategy = .reload

        var predicates: [NSPredicate] = []

        if let basePredicate = scope.predicate {
            predicates.append(basePredicate)
        }

        if let type = type {
            predicates.append(type.predicate)
        }

        for tagID in tagIDs {
            predicates.append(NSPredicate(format: "%K CONTAINS %@", #keyPath(Item.tags), tagID))
        }

        updatePredicate(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
    }

    private func switchLayout(_ layout: ItemLayout) {
        guard let dataSource = dataSource else { return }

        var snapshot = dataSource.snapshot()
        snapshot.reloadItems(snapshot.itemIdentifiers)

        dataSource.applySnapshotUsingReloadData(snapshot) { [unowned self] in
            switchLayout.send(layout)
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension ItemListViewModel {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        didChangeContent(with: snapshot)
    }
}
