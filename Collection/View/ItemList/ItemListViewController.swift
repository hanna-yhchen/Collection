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
    // MARK: - Properties

    private let viewModel: ItemListViewModel
    private lazy var boardID: ObjectID = viewModel.boardID

    private let itemManager: ItemManager
    private let storageProvider: StorageProvider
    private var previewingItem: PreviewItem?

    private lazy var collectionView = ItemCollectionView(frame: view.bounds, traits: view.traitCollection)

    var placeholderView: HintPlaceholderView?
    var isShowingPlaceholder = false

    @IBOutlet var plusButton: UIButton!
    private lazy var optionButton = UIBarButtonItem(image: UIImage(systemName: "slider.horizontal.3"))

    private var topContentOffset: CGPoint?

    private lazy var subscriptions = CancellableSet()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        addBindings()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        calculateTopContentOffset()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionView.setLayout(viewModel.currentLayout, animated: false)
        viewModel.fetchItems()
    }

    // MARK: - Initializers

    init?(
        coder: NSCoder,
        viewModel: ItemListViewModel,
        storageProvider: StorageProvider,
        itemManager: ItemManager = ItemManager.shared
    ) {
        self.viewModel = viewModel
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
        title = viewModel.title

        plusButton.layer.shadowColor = UIColor.black.cgColor
        plusButton.layer.shadowOpacity = 0.7
        plusButton.layer.shadowOffset = CGSize(width: 0, height: 2)

        view.insertSubview(collectionView, belowSubview: plusButton)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self

        viewModel.configureDataSource(for: collectionView) { [unowned self] indexPath, item in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: viewModel.currentLayout.cellIdentifier,
                for: indexPath) as? ItemCell
            else { fatalError("#\(#function): Failed to dequeue ItemCollectionViewCell") }

            cell.configure(for: item)

            if let sender = cell as? any ItemActionSendable {
                sender.actionPublisher
                    .sink { [unowned self] itemAction, itemID in
                        performItemAction(itemAction, itemID: itemID)
                    }
                    .store(in: &sender.subscriptions)
            }

            return cell
        }

        navigationItem.rightBarButtonItem = optionButton
    }

    private func addBindings() {
        viewModel.shouldDisplayPlaceholder
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] shouldDisplay in
                if shouldDisplay {
                    showPlaceholderView()
                } else {
                    removePlaceholderView()
                }
            }
            .store(in: &subscriptions)

        viewModel.currentMenu
            .receive(on: DispatchQueue.main)
            .assign(to: \.menu, on: optionButton)
            .store(in: &subscriptions)

        viewModel.switchLayout
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] layout in
                collectionView.setLayout(layout, animated: true)
                if let topContentOffset = topContentOffset {
                    collectionView.setContentOffset(topContentOffset, animated: true)
                }
            }
            .store(in: &subscriptions)
    }

    private func performItemAction(_ itemAction: ItemAction, itemID: ObjectID) {
        switch itemAction {
        case .rename:
            showNameEditor(itemID: itemID)
        case .tags:
            showTagSelector(itemID: itemID)
        case .move:
            showBoardSelector(scenario: .move(itemID))
        case .copy:
            showBoardSelector(scenario: .copy(itemID))
        case .delete:
            showDeletionAlert(itemID: itemID)
        }
    }

    private func showNameEditor(itemID: ObjectID) {
        let context = storageProvider.persistentContainer.viewContext
        guard let item = try? context.existingObject(with: itemID) as? Item else {
            HUD.showFailed(Constant.Message.missingData)
            return
        }
        let nameEditorVC = UIStoryboard.main.instantiateViewController(
            identifier: NameEditorViewController.storyboardID
        ) { NameEditorViewController(coder: $0, originalName: item.name) }

        nameEditorVC.modalPresentationStyle = .overCurrentContext
        nameEditorVC.cancellable = nameEditorVC.newNamePublisher
            .sink { [unowned self] newName in
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
    }

    private func showTagSelector(itemID: ObjectID) {
        let context = storageProvider.persistentContainer.viewContext

        guard
            let item = try? context.existingObject(with: itemID) as? Item,
            let board = item.board
        else {
            HUD.showFailed(Constant.Message.missingData)
            return
        }

        let viewModel = TagSelectorViewModel(
            storageProvider: storageProvider,
            itemID: itemID,
            boardID: board.objectID,
            context: context)
        let selectorVC = UIStoryboard.main.instantiateViewController(
            identifier: TagSelectorViewController.storyboardID
        ) { TagSelectorViewController(coder: $0, viewModel: viewModel) }

        let nav = UINavigationController(rootViewController: selectorVC)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = Constant.Layout.sheetCornerRadius
        }

        present(nav, animated: true)
    }

    private func showBoardSelector(scenario: BoardSelectorViewModel.Scenario) {
        let viewModel = BoardSelectorViewModel(scenario: scenario)
        let selectorVC = UIStoryboard.main.instantiateViewController(
            identifier: BoardSelectorViewController.storyboardID
        ) { BoardSelectorViewController(coder: $0, viewModel: viewModel) }

        present(selectorVC, animated: true)
    }

    private func showDeletionAlert(itemID: ObjectID) {
        let context = storageProvider.persistentContainer.viewContext

        let alert = UIAlertController(
            title: "Delete the item",
            message: "Are you sure you want to delete this item permanently?",
            preferredStyle: UIDevice.current.userInterfaceIdiom == .phone ? .actionSheet : .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) {[unowned self] _ in
            HUD.showProcessing()

            Task {
                do {
                    try await itemManager.deleteItem(
                        itemID: itemID,
                        context: context)
                    HUD.showSucceeded("Deleted")
                } catch {
                    print("#\(#function): Failed to delete board, \(error)")
                    HUD.showFailed()
                }
            }
        })
        present(alert, animated: true)
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
            HUD.showFailed()
            return
        }

        let picker = UIImagePickerController()
        picker.sourceType = camera
        picker.mediaTypes = [UTType.movie.identifier, UTType.image.identifier]
        picker.delegate = self

        present(picker, animated: true)
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
                    HUD.showProcessing()

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
        let context = storageProvider.persistentContainer.viewContext

        guard
            let item = context.object(with: id) as? Item,
            let displayType = DisplayType(rawValue: item.displayType)
        else {
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
            HUD.showFailed("Missing data information")
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
            HUD.showFailed("Unable to read the file")
            return
        }

        guard QLPreviewController.canPreview(fileURL as QLPreviewItem) else {
            HUD.showFailed("Preview of this file type is not supported")
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
            HUD.showFailed()
            return
        }

        let safariController = SFSafariViewController(url: url)
        safariController.preferredControlTintColor = .tintColor
        safariController.dismissButtonStyle = .close
        present(safariController, animated: true)
    }

    private func calculateTopContentOffset() {
        guard topContentOffset != nil else { return }
        let statusBarHeight = view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        let navBarHeight = navigationController?.navigationBar.frame.height ?? 0
        let safeAreaHeight = statusBarHeight + navBarHeight
        topContentOffset = CGPoint(x: 0, y: -safeAreaHeight)
    }
}

// MARK: - UICollectionViewDelegate

extension ItemListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = viewModel.objectID(for: indexPath) else { return }

        showItem(id: itemID)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let itemID = viewModel.objectID(for: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let children = ItemAction.allCases.map { itemAction in
                let action = UIAction(title: itemAction.title) { [unowned self] _ in
                    performItemAction(itemAction, itemID: itemID)
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
        self.collectionView.itemSize(for: viewModel.currentLayout)
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
        HUD.showProcessing()

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

            viewModel.reconfigureItems([itemID])
        }
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        previewingItem = nil
    }

    func previewController(_ controller: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {
        guard
            let previewItem = item as? PreviewItem,
            let indexPath = viewModel.indexPath(for: previewItem.objectID),
            let cell = collectionView.cellForItem(at: indexPath) as? ItemCell
        else { return nil }

        return cell.viewForZooming
    }
}
