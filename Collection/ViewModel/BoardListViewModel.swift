//
//  BoardListViewModel.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/14.
//

import CloudKit
import Combine
import CoreData
import UIKit

final class BoardListViewModel: NSObject, FetchedResultsProviding {
    // MARK: - Properties

    private let storageProvider: StorageProvider

    lazy var shouldDisplayPlaceholder = PassthroughSubject<Bool, Never>()

    let context: NSManagedObjectContext
    lazy var fetchedResultsController: NSFetchedResultsController<Board> = {
        let fetchRequest = Board.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Board.name), "Inbox")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Board.sortOrder, ascending: false)]
        fetchRequest.shouldRefreshRefetchedObjects = true

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: storageProvider.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        controller.delegate = self

        return controller
    }()

    var dataSource: DataSource?

    // MARK: - Initializer

    init(storageProvider: StorageProvider) {
        self.storageProvider = storageProvider
        self.context = storageProvider.persistentContainer.viewContext

        super.init()

        fetchedResultsController.delegate = self
    }

    // MARK: - Methods

    func addBoard(name: String) throws {
        try storageProvider.addBoard(name: name)
    }

    func deleteBoard(boardID: ObjectID) async throws {
        try await storageProvider.deleteBoard(
            boardID: boardID,
            context: context)
    }

    func ckShare(boardID: ObjectID) async throws -> CKShare {
        guard let board = object(with: boardID) else {
            throw CoreDataError.unfoundObjectInContext
        }

        let share: CKShare

        if let existingShare = board.shareRecord {
            share = existingShare
        } else {
            let (_, newShare, _) = try await storageProvider.persistentContainer.share([board], to: nil)
            share = newShare
        }

        share[CKShare.SystemFieldKey.title] = board.name
        if let image = UIImage(named: "logo-icon"), let data = image.jpegData(compressionQuality: 0.5) {
            share[CKShare.SystemFieldKey.thumbnailImageData] = data
        }

        return share
    }

    func applySnapshot(_ snapshot: Snapshot) {
        guard let dataSource = dataSource else { return }
        dataSource.apply(snapshot)
        shouldDisplayPlaceholder.send(snapshot.numberOfItems == 0 ? true : false)
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension BoardListViewModel {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        didChangeContent(with: snapshot)
    }
}
