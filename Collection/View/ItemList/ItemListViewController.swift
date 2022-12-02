//
//  ItemListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/28.
//

import CoreData
import Combine
import PhotosUI
import QuickLook
import SafariServices
import UniformTypeIdentifiers
import UIKit

class ItemListViewController: UIViewController, PlaceholderViewDisplayable {

    enum Scope {
        case allItems
        case board(ObjectID)
        case tag(ObjectID)

        var predicate: NSPredicate? {
            switch self {
            case .allItems:
                return nil
            case .board(let boardID):
                return NSPredicate(format: "%K == %@", #keyPath(Item.board), boardID)
            case .tag(let tagID):
                return NSPredicate(format: "%K CONTAINS %@", #keyPath(Item.tags), tagID)
            }
        }
    }

    enum SnapshotStrategy {
        case normal
        case reload
    }

    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
    typealias DataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>

    // MARK: - Properties

    private let scope: Scope
    private var snapshotStrategy: SnapshotStrategy = .normal

    #warning("NEED refactoring. This is only used for importing now.")
    private lazy var boardID: ObjectID = {
        switch scope {
        case .allItems, .tag:
            return storageProvider.getInboxBoardID()
        case .board(let boardID):
            return boardID
        }
    }()

    private let itemManager: ItemManager
    private let storageProvider: StorageProvider
    private let menuProvider: OptionMenuProvider

    // TODO: move fetchedResultsController logic to viewModel
    private lazy var fetchedResultsController: NSFetchedResultsController<Item> = {
        let fetchRequest = Item.fetchRequest()
        fetchRequest.predicate = scope.predicate
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
    private var subscriptions = CancellableSet()

    private lazy var collectionView = ItemCollectionView(frame: view.bounds, traits: view.traitCollection)
    var placeholderView: HintPlaceholderView?

    @IBOutlet var plusButton: UIButton!
    private lazy var optionButton = UIBarButtonItem(
        image: UIImage(systemName: "slider.horizontal.3"),
        menu: menuProvider.currentMenu)

    private var topContentOffset: CGPoint?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        addObservers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if topContentOffset == nil {
            let statusBarHeight = view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
            let navBarHeight = navigationController?.navigationBar.frame.height ?? 0
            let safeAreaHeight = statusBarHeight + navBarHeight
            topContentOffset = CGPoint(x: 0, y: -safeAreaHeight)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionView.setLayout(menuProvider.currentLayout, animated: false)
        try? fetchedResultsController.performFetch()
    }

    // MARK: - Initializers

    init?(
        coder: NSCoder,
        scope: Scope,
        storageProvider: StorageProvider,
        itemManager: ItemManager = ItemManager.shared,
        menuProvider: OptionMenuProvider = OptionMenuProvider()
    ) {
        self.scope = scope
        self.storageProvider = storageProvider
        self.itemManager = itemManager
        self.menuProvider = menuProvider

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
                sheet.detents = [.custom { _ in importController.sheetHeight }]
            } else {
                sheet.detents = [.medium()]
            }
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = 30
        }

        present(importController, animated: true)
    }
}

// MARK: - Private

extension ItemListViewController {
    private func configureHierarchy() {
        switch scope {
        case .allItems:
            title = "All Items"
        case .board(let boardID):
            let context = storageProvider.persistentContainer.viewContext
            do {
                guard let board = try context.existingObject(with: boardID) as? Board else {
                    fatalError("#\(#function): failed to downcast to board object")
                }
                title = board.name
            } catch {
                fatalError("#\(#function): failed to retrieve board object by id, \(error)")
            }
        case .tag(let tagID):
            plusButton.isHidden = true

            let context = storageProvider.persistentContainer.viewContext
            do {
                guard let tag = try context.existingObject(with: tagID) as? Tag else {
                    fatalError("#\(#function): failed to downcast to board object")
                }
                title = tag.name
            } catch {
                fatalError("#\(#function): failed to retrieve board object by id, \(error)")
            }
        }

        plusButton.layer.shadowColor = UIColor.black.cgColor
        plusButton.layer.shadowOpacity = 0.7
        plusButton.layer.shadowOffset = CGSize(width: 0, height: 2)

        view.insertSubview(collectionView, belowSubview: plusButton)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self

        navigationItem.rightBarButtonItem = optionButton
    }

    private func createDataSource() -> DataSource {
        DataSource(collectionView: collectionView) {[unowned self] collectionView, indexPath, objectID in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: menuProvider.currentLayout.cellIdentifier,
                for: indexPath) as? ItemCell
            else { fatalError("#\(#function): Failed to dequeue ItemCollectionViewCell") }

            guard let item = try? fetchedResultsController
                .managedObjectContext
                .existingObject(with: objectID) as? Item
            else { fatalError("#\(#function): Failed to retrieve item by objectID") }

            cell.configure(for: item)

            if let sender = cell as? ItemActionSendable {
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
            let context = fetchedResultsController.managedObjectContext
            let item = try? context.existingObject(with: itemID) as? Item
            let nameEditorVC = UIStoryboard.main
                .instantiateViewController(identifier: NameEditorViewController.storyboardID) { coder in
                    NameEditorViewController(coder: coder, originalName: item?.name)
                }

            nameEditorVC.modalPresentationStyle = .overCurrentContext
            nameEditorVC.cancellable = nameEditorVC.newNamePublisher
                .sink {[unowned self] newName in
                    Task {
                        do {
                            try await itemManager.updateItem(
                                itemID: itemID,
                                name: newName,
                                context: context)
                            await MainActor.run {
                                nameEditorVC.animateDismissSheet()
                            }
                        } catch {
                            HUD.showFailed()
                            print("#\(#function): Failed to rename item, \(error)")
                        }
                    }
                }

            present(nameEditorVC, animated: false)
        case .tags:
            let context = fetchedResultsController.managedObjectContext

            guard
                let item = try? context.existingObject(with: itemID) as? Item,
                let board = item.board
            else {
                HUD.showFailed(message: "Missing data")
                return
            }

            let selectorVC = UIStoryboard.main
                .instantiateViewController(identifier: TagSelectorViewController.storyboardID) { coder in
                    let viewModel = TagSelectorViewModel(
                        storageProvider: self.storageProvider,
                        itemID: itemID,
                        boardID: board.objectID,
                        context: context)
                    return TagSelectorViewController(coder: coder, viewModel: viewModel)
                }

            let nav = UINavigationController(rootViewController: selectorVC)
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.preferredCornerRadius = 30
            }

            present(nav, animated: true)
//        case .comments:
//            break
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
            let alert = UIAlertController(
                title: "Delete the item",
                message: "Are you sure you want to delete this item permanently?",
                preferredStyle: UIDevice.current.userInterfaceIdiom == .phone ? .actionSheet : .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) {[unowned self] _ in
                Task {
                    do {
                        try await itemManager.deleteItem(
                            itemID: itemID,
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
            .map {[weak self] transactions -> [NSPersistentHistoryTransaction] in
                guard let `self` = self else { return [] }
                let itemEntityName = Item.entity().name

                return transactions.filter { transaction in
                    if let changes = transaction.changes {
                        switch self.scope {
                        case .allItems:
                            return changes.contains { $0.changedObjectID.entity.name == itemEntityName }
                        case .board(let boardID):
                            return changes.contains { $0.changedObjectID == boardID }
                        case .tag(let tagID):
                            return changes.contains { $0.changedObjectID == tagID }
                        }
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

        NotificationCenter.default.publisher(for: .tagObjectDidChange, object: storageProvider)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.snapshotStrategy = .reload
                try? self.fetchedResultsController.performFetch()
            }
            .store(in: &subscriptions)

        menuProvider.$currentLayout
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] layout in
                switchLayout(layout)
            }
            .store(in: &subscriptions)

        menuProvider.$currentSort
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] sort in
                switchSort(sort)
            }
            .store(in: &subscriptions)

        menuProvider.$currentFilterType
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] type in
                applyFilter(type)
            }
            .store(in: &subscriptions)

        menuProvider.$currentMenu
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .assign(to: \.menu, on: optionButton)
            .store(in: &subscriptions)
    }

    private func switchLayout(_ layout: ItemLayout) {
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems(snapshot.itemIdentifiers)

        dataSource.applySnapshotUsingReloadData(snapshot) { [unowned self] in
            collectionView.setLayout(layout, animated: true)
            if let topContentOffset = topContentOffset {
                collectionView.setContentOffset(topContentOffset, animated: true)
            }
        }
    }

    private func switchSort(_ sort: ItemSort) {
        snapshotStrategy = .reload
        let fetchRequest = fetchedResultsController.fetchRequest
        fetchRequest.sortDescriptors = [sort.sortDescriptor]
        try? fetchedResultsController.performFetch()
    }

    private func applyFilter(_ type: DisplayType?) {
        snapshotStrategy = .reload
        let fetchRequest = fetchedResultsController.fetchRequest

        var predicate: NSPredicate?
        if let type = type {
            if let basePredicate = scope.predicate {
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [basePredicate, type.predicate])
            } else {
                predicate = type.predicate
            }
        } else {
            predicate = scope.predicate
        }
        fetchRequest.predicate = predicate

        try? fetchedResultsController.performFetch()
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
            .instantiateViewController(identifier: NoteEditorViewController.storyboardID) { coder in
                let viewModel = NoteEditorViewModel(
                    itemManager: self.itemManager,
                    scenario: .create(boardID: self.boardID))
                return NoteEditorViewController(coder: coder, viewModel: viewModel)
            }

        if let sheet = editorVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = 30
        }

        present(editorVC, animated: true)
    }

    private func showAudioRecorder() {
        let recorderVC = UIStoryboard.main
            .instantiateViewController(identifier: AudioRecorderController.storyboardID) { coder in
                return AudioRecorderController(coder: coder) {[unowned self] result in
                    HUD.showProgressing()

                    switch result {
                    case .success(let record):
                        Task {
                            do {
                                try await itemManager.process(record, saveInto: boardID)
                            } catch {
                                print("#\(#function): Failed to save new record, \(error)")
                            }
                            dismissForSuccess()
                        }
                    case .failure(let error):
                        print("#\(#function): Failed to record new void memo, \(error)")
                        dismissForFailure()
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
            HUD.showFailed()
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
            HUD.showFailed()
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
            HUD.showFailed()
            return
        }


        guard QLPreviewController.canPreview(fileURL as QLPreviewItem) else {
            // TODO: show alert
            HUD.showFailed()
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
            HUD.showFailed()
            return
        }

        let safariController = SFSafariViewController(url: url)
        safariController.preferredControlTintColor = .tintColor
        safariController.dismissButtonStyle = .close
        present(safariController, animated: true)
    }

    @MainActor
    private func reconfigureItems(_ items: [NSManagedObjectID]) async {
        var newSnapshot = dataSource.snapshot()
        newSnapshot.reconfigureItems(items)
        await dataSource.apply(newSnapshot, animatingDifferences: true)
    }
}

// MARK: - UICollectionViewDelegate

extension ItemListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return }

        showItem(id: itemID)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let children = ItemAction.allCases.map { itemAction in
                let action = UIAction(title: itemAction.title) { [unowned self] _ in
                    perform(itemAction, itemID: itemID)
                }
                if itemAction == .delete {
                    action.attributes = .destructive
                }
                return action
            }
            return UIMenu(children: children)
        }
    }
}

extension ItemListViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        self.collectionView.itemSize(for: menuProvider.currentLayout)
    }
}

// MARK: - UIDocumentPickerDelegate

extension ItemListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        HUD.showImporting()

        Task {
            do {
                try await itemManager.process(urls, saveInto: boardID)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                    HUD.showSucceeded()
                }
            } catch {
                print("#\(#function): Failed to process input from document picker, \(error)")
                HUD.showFailed()
            }
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension ItemListViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }

        HUD.showImporting()

        Task {
            do {
                #if targetEnvironment(simulator)
                try await itemManager.process(results.map(\.itemProvider), saveInto: boardID)
                #else
                try await itemManager.process(results.map(\.itemProvider), saveInto: boardID, isSecurityScoped: false)
                #endif

                HUD.showSucceeded()
            } catch {
                print("#\(#function): Failed to process input from photo picker, \(error)")
                dismissForFailure()
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate & UINavigationControllerDelegate

extension ItemListViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        HUD.showProgressing()

        guard
            let typeIdentifier = info[.mediaType] as? String,
            let type = UTType(typeIdentifier)
        else {
            dismissForFailure()
            return
        }

        switch type {
        case .image:
            guard let image = info[.originalImage] as? UIImage else {
                dismissForFailure()
                return
            }

            Task {
                await itemManager.process(image, saveInto: boardID)
                dismissForSuccess()
            }
        case .movie:
            guard let movieURL = info[.mediaURL] as? URL else {
                dismissForFailure()
                return
            }

            Task {
                do {
                    try await itemManager.process([movieURL], saveInto: boardID, isSecurityScoped: false)
                    dismissForSuccess()
                } catch {
                    print("#\(#function): Failed to process movie captured from image picker, \(error)")
                    dismissForFailure()
                }
            }
        default:
            dismissForFailure()
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension ItemListViewController: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var newSnapshot = snapshot as Snapshot

        if newSnapshot.numberOfItems == 0, placeholderView == nil {
            showPlaceholderView()
        } else if placeholderView != nil {
            removePlaceholderView()
        }

        if snapshotStrategy == .normal {
            let currentSnapshot = dataSource.snapshot()

            let updatedIDs = newSnapshot.itemIdentifiers.filter { objectID in
                guard
                    let currentIndex = currentSnapshot.indexOfItem(objectID),
                    let newIndex = newSnapshot.indexOfItem(objectID),
                    newIndex == currentIndex,
                    let item = try? controller.managedObjectContext.existingObject(with: objectID) as? Item
                else { return false }

                if let tags = item.tags?.allObjects as? [Tag], tags.contains(where: { $0.isUpdated }) {
                    return true
                }

                return item.isUpdated
            }
            newSnapshot.reloadItems(updatedIDs)
        } else {
            newSnapshot.reloadItems(newSnapshot.itemIdentifiers)
        }

        dataSource.apply(newSnapshot, animatingDifferences: true)
        snapshotStrategy = .normal
    }
}

// MARK: - UIPasteConfigurationSupporting

extension ItemListViewController {
    override func paste(itemProviders: [NSItemProvider]) {
        guard !itemProviders.isEmpty else { return }

        HUD.showImporting()

        Task {
            do {
                try await itemManager.process(itemProviders, saveInto: boardID, isSecurityScoped: false)
                HUD.showSucceeded()
            } catch {
                print("#\(#function): Failed to process input from pasteboard, \(error)")
                HUD.showFailed()
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

            await reconfigureItems([itemID])
        }
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        previewingItem = nil
    }

    func previewController(_ controller: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {
        guard
            let previewItem = item as? PreviewItem,
            let indexPath = dataSource.indexPath(for: previewItem.objectID),
            let cell = collectionView.cellForItem(at: indexPath) as? ItemCell
        else { return nil }

        return cell.viewForZooming
    }
}
