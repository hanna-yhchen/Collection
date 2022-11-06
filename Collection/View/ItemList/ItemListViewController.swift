//
//  ItemListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/28.
//

import Combine
import CoreData
import UniformTypeIdentifiers
import UIKit

class ItemListViewController: UIViewController {

    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
    typealias DataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>

    private let boardID: NSManagedObjectID
    private lazy var board: Board = {
        let context = storageProvider.persistentContainer.viewContext
        do {
            guard let board = try context.existingObject(with: boardID) as? Board else {
                fatalError("#\(#function): failed to downcast to board object")
            }

            return board
        } catch let error as NSError {
            fatalError("#\(#function): failed to retrieve board object by id, \(error)")
        }
    }()

    private let importManager: ItemImportManager
//    private let thumbnailProvider: ThumbnailProvider
    private let storageProvider: StorageProvider
    // TODO: move fetchedResultsController logic to viewModel
    private lazy var fetchedResultsController: NSFetchedResultsController<Item> = {
        let fetchRequest = Item.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "board == %@", board)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Item.creationDate, ascending: false)]

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: storageProvider.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        controller.delegate = self

        return controller
    }()

    private var dataSource: DataSource?
    private var subscriptions: Set<AnyCancellable> = []

    @IBOutlet var collectionView: UICollectionView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = board.name
        navigationController?.navigationBar.prefersLargeTitles = true
        collectionView.collectionViewLayout = createCardLayout()
        configureDataSource()
        addObservers()
        importManager.completion = { error in
            if let error = error {
                print(error)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        try? fetchedResultsController.performFetch()
    }

    convenience init?(
        coder: NSCoder,
        boardID: NSManagedObjectID,
        storageProvider: StorageProvider
    ) {
        let importManager = ItemImportManager(
            storageProvider: storageProvider,
            thumbnailProvider: ThumbnailProvider(),
            boardID: boardID)

        self.init(coder: coder, boardID: boardID, storageProvider: storageProvider, importManager: importManager)
    }

    init?(
        coder: NSCoder,
        boardID: NSManagedObjectID,
        storageProvider: StorageProvider,
        importManager: ItemImportManager
    ) {
        self.boardID = boardID
        self.storageProvider = storageProvider
        self.importManager = importManager

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @IBAction func addFileButtonTapped() {
        showDocumentPicker()
    }

    @IBAction func pasteButtonTapped() {
        paste(itemProviders: UIPasteboard.general.itemProviders)
    }

    @IBAction func addTextButtonTapped() {
        let editorVC = UIStoryboard.main
            .instantiateViewController(identifier: "EditorViewController") { coder in
                EditorViewController(coder: coder, situation: .create) {[weak self] name, note in
                    guard let `self` = self else { return }

                    self.storageProvider.addItem(
                        name: name,
                        contentType: UTType.plainText.identifier,
                        note: note,
                        boardID: self.boardID,
                        context: self.storageProvider.newTaskContext()
                    )
                }
            }
        navigationController?.pushViewController(editorVC, animated: true)
    }

    // MARK: - Private Methods

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<CardItemCell, NSManagedObjectID>(
            cellNib: UINib(nibName: CardItemCell.identifier, bundle: nil)
        ) {[unowned self] cell, _, objectID in
            guard let item = try? fetchedResultsController
                .managedObjectContext
                .existingObject(with: objectID) as? Item
            else { fatalError("#\(#function): Failed to retrieve item by objectID") }

            cell.layoutItem(item)
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

                let boardTransactions = self.currentBoardTransactions(from: transactions)
                guard !boardTransactions.isEmpty else { return }
                self.storageProvider.mergeTransactions(
                    boardTransactions,
                    to: self.fetchedResultsController.managedObjectContext)
            }
            .store(in: &subscriptions)
    }


    private func showDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = self
        picker.allowsMultipleSelection = true

        present(picker, animated: true)
    }

    private func createCardLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalWidth(0.5))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            subitem: item,
            count: 1)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 8
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func currentBoardTransactions(from transactions: [NSPersistentHistoryTransaction]) -> [NSPersistentHistoryTransaction] {
        transactions.filter { transaction in
            if let changes = transaction.changes {
                return changes.contains { $0.changedObjectID == boardID }
            }
            return false
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension ItemListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importManager.process(urls) { error in
            // TODO: UI reaction
            if let error = error {
                print("#\(#function): Failed to process input from document picker, \(error)")
            }
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension ItemListViewController: NSFetchedResultsControllerDelegate {
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

// MARK: - UIPasteConfigurationSupporting

extension ItemListViewController {
    override func paste(itemProviders: [NSItemProvider]) {
        importManager.processPasteboard(itemProviders: itemProviders) { error in
            // TODO: UI reaction
            if let error = error {
                print("#\(#function): Failed to process input from document picker, \(error)")
            }
        }
    }
}
