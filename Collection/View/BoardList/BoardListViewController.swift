//
//  BoardListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import CloudKit
import CoreData
import UIKit

class BoardListViewController: UIViewController, PlaceholderViewDisplayable {

    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
    typealias DataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>

    private let storageProvider: StorageProvider
    // TODO: move fetchedResultsController logic to viewModel
    private lazy var fetchedResultsController: NSFetchedResultsController<Board> = {
        let fetchRequest = Board.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Board.name), "Inbox")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Board.sortOrder, ascending: false)]

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: storageProvider.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        controller.delegate = self

        return controller
    }()

    private var dataSource: DataSource?
    private lazy var subscriptions = CancellableSet()

    @IBOutlet var collectionView: UICollectionView!
    var placeholderView: HintPlaceholderView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Boards"
        navigationController?.navigationBar.prefersLargeTitles = true
        configureCollectionView()
        configureDataSource()
        addObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        try? fetchedResultsController.performFetch()
    }

    init?(coder: NSCoder, storageProvider: StorageProvider) {
        self.storageProvider = storageProvider

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @IBAction func addButtonTapped() {
        let alert = UIAlertController(title: "New board", message: "", preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "Please enter a name for the new board."
        }

        alert.addAction(UIAlertAction(title: "Create", style: .default) {[unowned self] _ in
            guard
                let textField = alert.textFields?[0],
                let name = textField.text
            else { return }

            if !name.isEmpty, name != "Inbox" {
                storageProvider.addBoard(name: name, context: storageProvider.newTaskContext())
            } else {
                // TODO: show warning
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    // MARK: - Private Methods

    private func configureCollectionView() {
        collectionView.collectionViewLayout = createCardLayout()
        collectionView.allowsSelection = true
        collectionView.delegate = self
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<BoardCell, NSManagedObjectID>(
            cellNib: UINib(nibName: BoardCell.identifier, bundle: nil)
        ) {[unowned self] cell, _, objectID in
            guard let board = try? fetchedResultsController
                .managedObjectContext
                .existingObject(with: objectID) as? Board
            else { fatalError("#\(#function): Failed to retrieve item by objectID") }

            cell.configure(for: board)

            cell.actionPublisher
                .sink { boardAction, boardID in
                    self.perform(boardAction, boardID: boardID)
                }
                .store(in: &cell.subscriptions)
        }

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
    }

    private func perform(_ action: BoardAction, boardID: ObjectID) {
        switch action {
        case .rename:
            let context = fetchedResultsController.managedObjectContext
            let board = try? context.existingObject(with: boardID) as? Board
            let nameEditorVC = UIStoryboard.main
                .instantiateViewController(identifier: NameEditorViewController.storyboardID) { coder in
                    NameEditorViewController(coder: coder, originalName: board?.name)
                }

            nameEditorVC.modalPresentationStyle = .overCurrentContext
            nameEditorVC.cancellable = nameEditorVC.newNamePublisher
                .sink {[unowned self] newName in
                    guard !newName.isEmpty else {
                        HUD.showFailed(message: "The name of a board cannot be empty.")
                        return
                    }

                    Task {
                        do {
                            try await storageProvider.updateBoard(
                                boardID: boardID,
                                name: newName,
                                context: context)
                            await MainActor.run {
                                nameEditorVC.animateDismissSheet()
                            }
                        } catch {
                            print("#\(#function): Failed to rename item, \(error)")
                        }
                    }
                }

            present(nameEditorVC, animated: false)
        case .share:
            startSharingFlow(boardID: boardID)
        case .delete:
            let alert = UIAlertController(
                title: "Delete the board",
                message: "Are you sure you want to delete this board permanently?",
                preferredStyle: UIDevice.current.userInterfaceIdiom == .phone ? .actionSheet : .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) {[unowned self] _ in
                Task {
                    do {
                        try await storageProvider.deleteBoard(
                            boardID: boardID,
                            context: fetchedResultsController.managedObjectContext)
                    } catch {
                        print("#\(#function): Failed to delete board, \(error)")
                    }
                }
            })
            present(alert, animated: true)
        }
    }

    private func addObservers() {
        storageProvider.historyManager.storeDidChangePublisher
            .map { transactions -> [NSPersistentHistoryTransaction] in
                let boardEntityName = Board.entity().name

                return transactions.filter { transaction in
                    if let changes = transaction.changes {
                        return changes.contains { $0.changedObjectID.entity.name == boardEntityName }
                    }
                    return false
                }
            }
            .receive(on: DispatchQueue.main)
            .sink {[weak self] transactions in
                guard let self = self, !transactions.isEmpty else { return }

                self.storageProvider.mergeTransactions(
                    transactions,
                    to: self.fetchedResultsController.managedObjectContext)
            }
            .store(in: &subscriptions)
    }

    private func createCardLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(1))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            subitem: item,
            count: 1)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 8
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        return UICollectionViewCompositionalLayout(section: section)
    }

    // TODO: abstract sharing functionality into StorageProvider
    private func startSharingFlow(boardID: ObjectID) {
        HUD.showProgressing()

        Task {
            let context = fetchedResultsController.managedObjectContext
            guard let board = try? context.existingObject(with: boardID) as? Board else {
                HUD.showFailed()
                return
            }

            var share: CKShare?

            if let existingShare = board.shareRecord {
                share = existingShare
            } else {
                let semaphore = DispatchSemaphore(value: 0)
                self.storageProvider.persistentContainer.share([board], to: nil) { _, newShare, _, error in
                    if let error = error {
                        print("#\(#function): Failed to create new share, \(error)")
                    }
                    share = newShare
                    semaphore.signal()
                }
                semaphore.wait()
            }

            guard let share = share else {
                HUD.showFailed()
                return
            }

            share[CKShare.SystemFieldKey.title] = board.name
            if let image = UIImage(named: "logo-icon"), let data = image.jpegData(compressionQuality: 0.5) {
                share[CKShare.SystemFieldKey.thumbnailImageData] = data
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                let sharingController = UICloudSharingController(
                    share: share,
                    container: self.storageProvider.cloudKitContainer)
                sharingController.delegate = self
                sharingController.modalPresentationStyle = .formSheet
                self.present(sharingController, animated: true) {
                    HUD.dismiss()
                }
            }
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension BoardListViewController: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        guard let dataSource = dataSource else { fatalError("#\(#function): Failed to unwrap data source") }

        var newSnapshot = snapshot as Snapshot
        if newSnapshot.numberOfItems == 0 {
            showPlaceholderView()
        } else if placeholderView != nil {
            removePlaceholderView()
        }

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

        let shouldAnimate = collectionView.numberOfSections != 0
        dataSource.apply(newSnapshot, animatingDifferences: shouldAnimate)
    }
}

// MARK: - UICollectionViewDelegate

extension BoardListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let boardID = dataSource?.itemIdentifier(for: indexPath) else { return }

        let itemListVC = UIStoryboard.main
            .instantiateViewController(identifier: ItemListViewController.storyboardID) { coder in
                ItemListViewController(
                    coder: coder,
                    scope: .board(boardID),
                    storageProvider: self.storageProvider)
            }
        navigationController?.pushViewController(itemListVC, animated: true)
    }
}

// MARK: - UICloudSharingControllerDelegate

extension BoardListViewController: UICloudSharingControllerDelegate {
    func itemTitle(for csc: UICloudSharingController) -> String? {
        nil
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("#\(#function): Failed to save share, \(error)")
    }
}
