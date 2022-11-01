//
//  ItemListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/28.
//

import CoreData
import UniformTypeIdentifiers
import UIKit

class ItemListViewController: UIViewController {

    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
    typealias DataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>

    private let thumbnailProvider: ThumbnailProvider
    private let storageProvider: StorageProvider
    private lazy var fetchedResultsController: NSFetchedResultsController<Item> = {
        let fetchRequest = Item.fetchRequest()
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

    @IBOutlet var collectionView: UICollectionView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "All Items"
        navigationController?.navigationBar.prefersLargeTitles = true
        collectionView.collectionViewLayout = createCardLayout()
        configureDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        try? fetchedResultsController.performFetch()
    }

    init?(coder: NSCoder, storageProvider: StorageProvider, thumbnailProvider: ThumbnailProvider = ThumbnailProvider()) {
        self.storageProvider = storageProvider
        self.thumbnailProvider = thumbnailProvider

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
                    self?.storageProvider.addItem(
                        name: name,
                        contentType: UTType.plainText.identifier,
                        note: note)
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

    private func readAndSave(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            // TODO: show failure alert
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        var error: NSError?

        NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { url in
            guard
                let values = try? url.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey]),
                let size = values.fileSize,
                size <= 20_000_000,
                let type = values.contentType,
                let name = values.name,
                let data = try? Data(contentsOf: url)
            else {
                // TODO: show alert
                return
            }

            let semaphore = DispatchSemaphore(value: 0)

            Task {
                defer { semaphore.signal() }

                let thumbnailResult = await self.thumbnailProvider.generateThumbnailData(url: url)

                var thumbnailData: Data?

                switch thumbnailResult {
                case .success(let data):
                    thumbnailData = data
                case .failure(let error):
                    print("#\(#function): Failed to generate thumbnail data, \(error)")
                }

                self.storageProvider.addItem(
                    name: name,
                    contentType: type.identifier,
                    itemData: data,
                    thumbnailData: thumbnailData)
            }

            semaphore.wait()
        }

        if let error = error {
            print("#\(#function): Error reading input data, \(error)")
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension ItemListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        urls.forEach { url in
            DispatchQueue.global().async {
                self.readAndSave(url)
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
        guard
            let provider = itemProviders.first,
            provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
        else {
            // TODO: show failure alert
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            guard
                let urlString = UIPasteboard.general.string,
                let data = urlString.data(using: .utf8)
            else {
                // TODO: show failure alert
                return
            }

            storageProvider.addItem(
                name: urlString,
                contentType: UTType.url.identifier,
                itemData: data
            )
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
            let text = UIPasteboard.general.string
            let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
            let name = "Pasted note \(currentTime)"
            storageProvider.addItem(
                name: name,
                contentType: UTType.plainText.identifier,
                note: text
            )
            return
        }

        guard let type = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier) != nil
        }) else {
            // TODO: show failure alert
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: type) {[weak self] url, error in
            guard let `self` = self else { return }

            if let error = error {
                print("#\(#function): Error loading data from pasteboard, \(error)")
                return
            }

            guard let url = url else {
                print("#\(#function): Failed to retrieve url for loaded file")
                return
            }

            self.readAndSave(url)
        }
    }
}
