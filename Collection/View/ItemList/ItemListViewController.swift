
//  ItemListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/28.
//

import Combine
import CoreData
import PhotosUI
import QuickLook
import SafariServices
import UniformTypeIdentifiers
import UIKit

class ItemListViewController: UIViewController, UIPopoverPresentationControllerDelegate {

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

    private let itemManager: ItemManager
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

    private lazy var previewController = QLPreviewController()
    private var previewingURL: URL? {
        didSet {
            if previewingURL != nil {
                previewController.reloadData()
            }
        }
    }
    private var previewingItem: Item?

    private var dataSource: DataSource?
    private var subscriptions: Set<AnyCancellable> = []

    @IBOutlet var collectionView: ItemCollectionView!
    @IBOutlet var plusButton: UIButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = board.name
//        addButtonStack()
        plusButton.layer.shadowColor = UIColor.black.cgColor
        plusButton.layer.shadowOpacity = 0.7
        plusButton.layer.shadowOffset = CGSize(width: 0, height: 2)

        view.layoutIfNeeded()
        collectionView.traits = view.traitCollection
        collectionView.setTwoColumnLayout(animated: false)
        collectionView.delegate = self

        previewController.dataSource = self
        previewController.delegate = self
        configureDataSource()
        addObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        try? fetchedResultsController.performFetch()
    }

    init?(
        coder: NSCoder,
        boardID: NSManagedObjectID,
        storageProvider: StorageProvider,
        itemManager: ItemManager = ItemManager.shared
    ) {
        self.boardID = boardID
        self.storageProvider = storageProvider
        self.itemManager = itemManager

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @IBAction func plusButtonTapped() {
        guard let importController = UIStoryboard.main.instantiateViewController(withIdentifier: ItemImportController.storyboardID) as? ItemImportController else { return }

        importController.selectMethod
            .receive(on: DispatchQueue.main)
            .sink {[unowned self] method in
                switch method {
                case .paste:
                    pasteButtonTapped()
                case .photos:
                    addPhotoButtonTapped()
                case .camera:
                    cameraButtonTapped()
                case .files:
                    addFileButtonTapped()
                case .note:
                    addNoteButtonTapped()
                case .audioRecorder:
                    voiceButtonTapped()
                }
            }
            .store(in: &subscriptions)

        // TODO: pop over
        preferredContentSize = CGSize(width: view.bounds.width, height: 300)
            if let sheet = importController.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.preferredCornerRadius = 30
            }

            present(importController, animated: true)
        }


    @objc private func addFileButtonTapped() {
        showDocumentPicker()
    }

    @objc private func pasteButtonTapped() {
        paste(itemProviders: UIPasteboard.general.itemProviders)
    }

    @objc private func addNoteButtonTapped() {
        let editorVC = UIStoryboard.main
            .instantiateViewController(identifier: EditorViewController.storyboardID) { coder in
                let viewModel = EditorViewModel(itemManager: self.itemManager, scenario: .create(boardID: self.boardID))
                return EditorViewController(coder: coder, viewModel: viewModel)
            }
        navigationController?.pushViewController(editorVC, animated: true)
    }

    @objc private func addPhotoButtonTapped() {
        showPhotoPicker()
    }

    @objc private func cameraButtonTapped() {
        openCamera()
    }

    @objc private func voiceButtonTapped() {
        showAudioRecorder()
    }

    // MARK: - Private Methods

    private func addButtonStack() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.spacing = 8

        let buttonConfigs: [(title: String, action: Selector)] = [
            ("Camera", #selector(cameraButtonTapped)),
            ("Voice", #selector(voiceButtonTapped)),
            ("Add Note", #selector(addNoteButtonTapped)),
            ("Add Files", #selector(addFileButtonTapped)),
            ("Add Photos", #selector(addPhotoButtonTapped)),
            ("Paste", #selector(pasteButtonTapped)),
        ]

        buttonConfigs.forEach { config in
            let button = UIButton(type: .system)
            button.setTitle(config.title, for: .normal)
            button.addTarget(self, action: config.action, for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }

        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<TwoColumnCell, NSManagedObjectID>(
            cellNib: UINib(nibName: TwoColumnCell.identifier, bundle: nil)
        ) {[unowned self] cell, _, objectID in
            guard let item = try? fetchedResultsController
                .managedObjectContext
                .existingObject(with: objectID) as? Item
            else { fatalError("#\(#function): Failed to retrieve item by objectID") }

            cell.configure(for: item)
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

    private func showPhotoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self

        present(picker, animated: true)
    }

    private func openCamera() {
        let camera = UIImagePickerController.SourceType.camera
        guard
            UIImagePickerController.isSourceTypeAvailable(camera),
            UIImagePickerController.availableMediaTypes(for: camera) != nil
        else {
            // TODO: show alert
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = camera
        picker.mediaTypes = [UTType.movie.identifier, UTType.image.identifier]
        picker.delegate = self

        self.present(picker, animated: true)
    }

    private func showAudioRecorder() {
        let recorderVC = UIStoryboard.main
            .instantiateViewController(identifier: AudioRecorderController.storyboardID) { coder in
                return AudioRecorderController(coder: coder) {[unowned self] result in
                    switch result {
                    case .success(let record):
                        Task {
                            do {
                                try await itemManager.process(record, saveInto: boardID)
                            } catch {
                                print("#\(#function): Failed to save new record, \(error)")
                            }
                            await MainActor.run {
                                dismiss(animated: true)
                            }
                        }
                    case .failure(let error):
                        print("#\(#function): Failed to record new void memo, \(error)")
                        dismiss(animated: true)
                    }
                }
            }

        if let sheet = recorderVC.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = 30
        }

        present(recorderVC, animated: true, completion: nil)
    }

    private func showItem(id: NSManagedObjectID) {
        let context = fetchedResultsController.managedObjectContext

        guard
            let item = context.object(with: id) as? Item,
            let displayType = DisplayType(rawValue: item.displayType),
            let typeIdentifier = item.uti,
            let itemType = UTType(typeIdentifier)
        else {
            // TODO: show alert
            return
        }

        if displayType == .note {
            showNotePreview(item)
            return
        }

        if displayType == .link {
            openLink(item)
            return
        }

        guard
            let data = item.itemData?.data, // Note item will filtered out here
            let uuid = item.uuid,
            let filenameExtension = itemType.preferredFilenameExtension
        else {
            // TODO: show alert
            return
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
            // TODO: show alert
            return
        }


        guard QLPreviewController.canPreview(fileURL as QLPreviewItem) else {
            // TODO: show alert
            return
        }

        self.previewingItem = item
        self.previewingURL = fileURL
        navigationController?.pushViewController(previewController, animated: true)
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

    private func showNotePreview(_ item: Item) {
        let noteVC = UIStoryboard.main
            .instantiateViewController(identifier: NotePreviewController.storyboardID) { coder in
                NotePreviewController(coder: coder, item: item, itemManager: self.itemManager)
            }
        navigationController?.pushViewController(noteVC, animated: true)
    }

    private func openLink(_ item: Item) {
        guard
            let data = item.itemData?.data,
            let url = URL(dataRepresentation: data, relativeTo: nil)
        else {
            // TODO: show alert
            return
        }

        let safariController = SFSafariViewController(url: url)
        safariController.preferredControlTintColor = .tintColor
        safariController.dismissButtonStyle = .close
        present(safariController, animated: true)
    }

    private func currentBoardTransactions(from transactions: [NSPersistentHistoryTransaction]) -> [NSPersistentHistoryTransaction] {
        transactions.filter { transaction in
            if let changes = transaction.changes {
                return changes.contains { $0.changedObjectID == boardID }
            }
            return false
        }
    }

    private func reloadItems(_ items: [NSManagedObjectID]) {
        Task { @MainActor in
            guard let dataSource = dataSource else { return }

            var newSnapshot = dataSource.snapshot()
            newSnapshot.reloadItems(items)
            await dataSource.apply(newSnapshot, animatingDifferences: true)
        }
    }
}

// MARK: - UICollectionViewDelegate

extension ItemListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = dataSource?.itemIdentifier(for: indexPath) else { return }

        showItem(id: itemID)
    }
}


// MARK: - UIDocumentPickerDelegate

extension ItemListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task {
            // TODO: UI reaction
            do {
                try await itemManager.process(urls, saveInto: boardID)
            } catch {
                print("#\(#function): Failed to process input from document picker, \(error)")
            }
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension ItemListViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        Task {
            // TODO: UI reaction
            do {
                #if targetEnvironment(simulator)
                try await itemManager.process(results.map(\.itemProvider), saveInto: boardID)
                #else
                try await itemManager.process(results.map(\.itemProvider), saveInto: boardID, isSecurityScoped: false)
                #endif
                await MainActor.run {
                    picker.dismiss(animated: true)
                }
            } catch {
                print("#\(#function): Failed to process input from photo picker, \(error)")
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate & UINavigationControllerDelegate

extension ItemListViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard
            let typeIdentifier = info[.mediaType] as? String,
            let type = UTType(typeIdentifier)
        else {
            picker.dismiss(animated: true)
            return
        }

        // TODO: UI reaction
        switch type {
        case .image:
            guard let image = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true)
                return
            }

            Task {
                await itemManager.process(image, saveInto: boardID)
                await MainActor.run {
                    picker.dismiss(animated: true)
                }
            }
        case .movie:
            guard let movieURL = info[.mediaURL] as? URL else {
                picker.dismiss(animated: true)
                return
            }

            Task {
                do {
                    try await itemManager.process([movieURL], saveInto: boardID, isSecurityScoped: false)
                } catch {
                    print("#\(#function): Failed to process movie captured from image picker, \(error)")
                }
                await MainActor.run {
                    picker.dismiss(animated: true)
                }
            }
        default:
            picker.dismiss(animated: true)
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
        Task {
            // TODO: UI reaction
            do {
                try await itemManager.process(itemProviders, saveInto: boardID, isSecurityScoped: false)
            } catch {
                print("#\(#function): Failed to process input from pasteboard, \(error)")
            }
        }
    }
}

// MARK: - QLPreviewControllerDataSource

extension ItemListViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewingURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        guard let previewItem = previewingURL as? QLPreviewItem else {
            fatalError("#\(#function): there should exist a non-nil preview item but not")
        }

        return previewItem
    }
}

// MARK: - QLPreviewControllerDelegate

extension ItemListViewController: QLPreviewControllerDelegate {
    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        .updateContents
    }

    func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: QLPreviewItem) {
        guard
            let url = previewItem as? URL,
            let itemID = previewingItem?.objectID
        else { return }

        Task {
            do {
                try await itemManager.updatePreviewingItem(itemID: itemID, url: url)
            } catch {
                print("\(#function): Failed to update changes on previewing item, \(error)")
            }

            reloadItems([itemID])
        }
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        previewingItem = nil
        previewingURL = nil
    }
}

extension ItemListViewController: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        self
    }
}
