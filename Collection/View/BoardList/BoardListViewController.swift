//
//  BoardListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import CloudKit
import Combine
import CoreData
import UIKit

class BoardListViewController: UIViewController {

    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
    typealias DataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>

    private let storageProvider: StorageProvider
    // TODO: move fetchedResultsController logic to viewModel
    private lazy var fetchedResultsController: NSFetchedResultsController<Board> = {
        let fetchRequest = Board.fetchRequest()
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
    private var boardToShare: Board?
    private var subscriptions: Set<AnyCancellable> = []

    @IBOutlet var collectionView: UICollectionView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "All Boards"
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

            if !name.isEmpty {
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

            cell.layoutBoard(board)
            // TODO: check share status to display different titles and implement corresponding logic
            cell.shareHandler = {[weak self] in
                self?.boardToShare = board
                self?.startSharingFlow()
            }
        }

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
    }

    private func addObservers() {
        storageProvider.historyManager?.storeDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink {[weak self] transactions in
                guard let `self` = self else { return }

                let boardTransactions = self.boardTransactions(from: transactions)
                guard !boardTransactions.isEmpty else { return }
                self.storageProvider.mergeTransactions(
                    boardTransactions,
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
            heightDimension: .fractionalHeight(1.0))
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
    private func startSharingFlow() {
        guard let board = boardToShare else {
            return
        }

        Task {
            guard let share = await newShare(board: board) else {
                // TODO: show failure alert
                return
            }

            let sharingController = UICloudSharingController(share: share, container: storageProvider.cloudKitContainer)
            sharingController.delegate = self
            sharingController.modalPresentationStyle = .formSheet

            await MainActor.run {
                present(sharingController, animated: true)
            }
        }
    }

    private func newShare(board: Board) async -> CKShare? {
        do {
            let (_, share, _) = try await storageProvider.persistentContainer.share([board], to: nil)
            share[CKShare.SystemFieldKey.title] = board.name
            return share
        } catch {
            print("#\(#function): Failed to create new CKShare, \(error)")
            return nil
        }
    }

    private func boardTransactions(from transactions: [NSPersistentHistoryTransaction]) -> [NSPersistentHistoryTransaction] {
        let boardEntityName = Board.entity().name

        return transactions.filter { transaction in
            if let changes = transaction.changes {
                return changes.contains { $0.changedObjectID.entity.name == boardEntityName }
            }
            return false
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension BoardListViewController: NSFetchedResultsControllerDelegate {
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
            .instantiateViewController(identifier: "ItemListViewController") { coder in
                ItemListViewController(
                    coder: coder,
                    boardID: boardID,
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
