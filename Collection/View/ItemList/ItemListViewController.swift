//
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

    private var previewingItem: PreviewItem?
    private lazy var dataSource = createDataSource()
    private var subscriptions: Set<AnyCancellable> = []

    private var currentLayout: ItemLayout = .smallCard
    private lazy var layoutActions: [UIAction] = {
        let actions = ItemLayout.allCases.map { layout in
            UIAction(
                title: layout.title,
                image: layout.buttonIcon
            ) { _ in
                self.changeLayout(layout)
            }
        }
        actions[1].state = .on
        return actions
    }()

    private lazy var collectionView = ItemCollectionView(frame: view.bounds, traits: view.traitCollection)

    @IBOutlet var plusButton: UIButton!
    @IBOutlet var layoutButton: UIBarButtonItem!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = board.name
        plusButton.layer.shadowColor = UIColor.black.cgColor
        plusButton.layer.shadowOpacity = 0.7
        plusButton.layer.shadowOffset = CGSize(width: 0, height: 2)

        view.insertSubview(collectionView, belowSubview: plusButton)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self

        layoutButton.menu = layoutMenu(selectedIndex: ItemLayout.smallCard.rawValue)

        addObservers()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionView.setLayout(currentLayout, animated: false)
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
        guard let importController = UIStoryboard.main.instantiateViewController(
            withIdentifier: ItemImportController.storyboardID) as? ItemImportController
        else { return }

        importController.selectMethod
            .receive(on: DispatchQueue.main)
            .sink {[unowned self] method in
                switch method {
                case .paste:
                    paste(itemProviders: UIPasteboard.general.itemProviders)
                case .photos:
                    showPhotoPicker()
                case .camera:
                    openCamera()
                case .files:
                    showDocumentPicker()
                case .note:
                    showNoteEditor()
                case .audioRecorder:
                    showAudioRecorder()
                }
            }
            .store(in: &subscriptions)

        importController.modalPresentationStyle = .formSheet
        importController.preferredContentSize = CGSize(width: 300, height: 400)
        if let sheet = importController.sheetPresentationController {
            if #available(iOS 16.0, *) {
                sheet.detents = [.custom { _ in 240 }]
            } else {
                sheet.detents = [.medium()]
            }
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = 30
        }

        present(importController, animated: true)
    }


    @IBAction func layoutButtonTapped() {
        let newLayout = currentLayout.next
        changeLayout(newLayout)
    }

    func changeLayout(_ layout: ItemLayout) {
        guard layout != currentLayout else { return }

        layoutButton.image = layout.buttonIcon

        layoutButton.menu = layoutMenu(selectedIndex: layout.rawValue)
        currentLayout = layout

        var snapshot = dataSource.snapshot()
        snapshot.reloadItems(snapshot.itemIdentifiers)
        dataSource.applySnapshotUsingReloadData(snapshot) {
            self.collectionView.setLayout(layout, animated: true)
        }
    }

    // MARK: - Private Methods

    private func createDataSource() -> DataSource {
        DataSource(collectionView: collectionView) {[unowned self] collectionView, indexPath, objectID in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: self.currentLayout.cellIdentifier,
                for: indexPath) as? ItemCell
            else { fatalError("#\(#function): Failed to dequeue ItemCollectionViewCell") }

            guard let item = try? fetchedResultsController
                .managedObjectContext
                .existingObject(with: objectID) as? Item
            else { fatalError("#\(#function): Failed to retrieve item by objectID") }

            cell.configure(for: item)

            if var sender = cell as? ItemActionSendable {
                sender.actionPublisher
                    .sink { itemAction, itemID in
                        self.perform(itemAction, itemID: itemID)
                    }
                    .store(in: &sender.subscriptions)
            }

            return cell
        }
    }

    private func perform(_ action: ItemAction, itemID: ObjectID) {
        switch action {
        case .rename:
            guard let nameEditorVC = UIStoryboard.main.instantiateViewController(
                withIdentifier: NameEditorViewController.storyboardID) as? NameEditorViewController
            else { fatalError("#\(#function): Failed downcast to NameEditorViewController") }

            nameEditorVC.modalPresentationStyle = .overCurrentContext
            nameEditorVC.cancellable = nameEditorVC.newNamePublisher
                .sink {[unowned self] newName in
                    Task {
                        do {
                            try await itemManager.updateItem(
                                itemID: itemID,
                                name: newName,
                                context: fetchedResultsController.managedObjectContext)
                            await MainActor.run {
                                nameEditorVC.animateDismissSheet()
                            }
                        } catch {
                            print("#\(#function): Failed to rename item, \(error)")
                        }
                    }
                }

            present(nameEditorVC, animated: false)
        case .tags:
            let selectorVC = UIStoryboard.main
                .instantiateViewController(identifier: TagSelectorViewController.storyboardID) { coder in
                    let viewModel = TagSelectorViewModel(storageProvider: self.storageProvider, itemID: itemID)
                    return TagSelectorViewController(coder: coder, viewModel: viewModel)
                }

            let nav = UINavigationController(rootViewController: selectorVC)
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.preferredCornerRadius = 30
            }

            present(nav, animated: true)
        case .comments:
            break
        case .move:
            let selectorVC = UIStoryboard.main
                .instantiateViewController(identifier: BoardSelectorViewController.storyboardID) { coder in
                    let viewModel = BoardSelectorViewModel(scenario: .move(itemID))
                    return BoardSelectorViewController(coder: coder, viewModel: viewModel)
                }

            present(selectorVC, animated: true)
        case .copy:
            let selectorVC = UIStoryboard.main
                .instantiateViewController(identifier: BoardSelectorViewController.storyboardID) { coder in
                    let viewModel = BoardSelectorViewModel(scenario: .copy(itemID))
                    return BoardSelectorViewController(coder: coder, viewModel: viewModel)
                }

            present(selectorVC, animated: true)
        case .delete:
            Task {
                do {
                    try await itemManager.deleteItem(
                        itemID: itemID,
                        context: fetchedResultsController.managedObjectContext)
                } catch {
                    print("#\(#function): Failed to delete item, \(error)")
                }
            }
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

    private func showNoteEditor() {
        let editorVC = UIStoryboard.main
            .instantiateViewController(identifier: EditorViewController.storyboardID) { coder in
                let viewModel = EditorViewModel(itemManager: self.itemManager, scenario: .create(boardID: self.boardID))
                return EditorViewController(coder: coder, viewModel: viewModel)
            }
        navigationController?.pushViewController(editorVC, animated: true)
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
            let displayType = DisplayType(rawValue: item.displayType)
        else {
            // TODO: show alert
            return
        }

        switch displayType {
        case .note:
            showNotePreview(item)
        case .link:
            openLink(item)
        default:
            showQuickLook(item)
        }
    }

    private func showQuickLook(_ item: Item) {
        guard
            let data = item.itemData?.data,
            let uuid = item.uuid,
            let typeIdentifier = item.uti,
            let itemType = UTType(typeIdentifier),
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

        self.previewingItem = PreviewItem(objectID: item.objectID, previewItemURL: fileURL, previewItemTitle: item.name)

        let previewController = QLPreviewController()
        previewController.dataSource = self
        previewController.delegate = self
        present(previewController, animated: true)
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
            var newSnapshot = dataSource.snapshot()
            newSnapshot.reloadItems(items)
            await dataSource.apply(newSnapshot, animatingDifferences: true)
        }
    }

    private func layoutMenu(selectedIndex: Int) -> UIMenu {
        for (index, action) in layoutActions.enumerated() {
            action.state = index == selectedIndex ? .on : .off
        }

        return UIMenu(
            title: "Display Mode",
            children: layoutActions)
    }
}

// MARK: - UICollectionViewDelegate

extension ItemListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return }

        showItem(id: itemID)
    }
}

extension ItemListViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        self.collectionView.itemSize(for: currentLayout)
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
        previewingItem == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        guard let previewItem = previewingItem else {
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
            let previewItem = previewItem as? PreviewItem,
            let url = previewItem.previewItemURL
        else { return }

        let itemID = previewItem.objectID

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
    }
}
