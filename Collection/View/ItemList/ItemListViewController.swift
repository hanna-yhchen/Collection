//
//  ItemListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/28.
//

import Combine
import QuickLook
import SafariServices
import UIKit
import PhotosUI

protocol ItemListViewControllerDelegate: AnyObject {
    func showItemImportController(handler: ImportMethodHandling, boardID: ObjectID)
    func showNameEditorViewController(itemID: ObjectID)
    func showBoardSelectorViewController(scenario: BoardSelectorViewModel.Scenario)
    func showTagSelectorViewController(itemID: ObjectID)
    func showDeletionAlert(object: ManagedObject)
}

class ItemListViewController: UIViewController, PlaceholderViewDisplayable {
    // MARK: - Properties

    private let viewModel: ItemListViewModel
    lazy var boardID: ObjectID = viewModel.boardID

    let itemManager: ItemManager
    private weak var delegate: ItemListViewControllerDelegate?
    private var previewingItem: PreviewItem?

    private lazy var collectionView = ItemCollectionView(frame: view.bounds, traits: view.traitCollection)

    var placeholderView: HintPlaceholderView?
    var isShowingPlaceholder = false

    @IBOutlet var plusButton: UIButton!
    private lazy var optionButton = UIBarButtonItem(image: UIImage(systemName: "slider.horizontal.3"))

    private var topContentOffset: CGPoint?

    lazy var subscriptions = CancellableSet()

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
        viewModel.performFetch()
    }

    // MARK: - Initializers

    init?(
        coder: NSCoder,
        viewModel: ItemListViewModel,
        itemManager: ItemManager = ItemManager.shared,
        delegate: ItemListViewControllerDelegate
    ) {
        self.viewModel = viewModel
        self.itemManager = itemManager
        self.delegate = delegate

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    @IBAction private func plusButtonTapped() {
        delegate?.showItemImportController(handler: self, boardID: boardID)
    }

    private func configureHierarchy() {
        title = viewModel.title

        plusButton.layer.shadowColor = UIColor.black.cgColor
        plusButton.layer.shadowOpacity = 0.7
        plusButton.layer.shadowOffset = CGSize(width: 0, height: 2)

        view.insertSubview(collectionView, belowSubview: plusButton)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self

        viewModel.configureDataSource(for: collectionView) { [unowned self] _, indexPath, item in
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
            delegate?.showNameEditorViewController(itemID: itemID)
        case .tags:
            delegate?.showTagSelectorViewController(itemID: itemID)
        case .move:
            delegate?.showBoardSelectorViewController(scenario: .move(itemID))
        case .copy:
            delegate?.showBoardSelectorViewController(scenario: .copy(itemID))
        case .delete:
            let itemObject = ManagedObject(entity: .item(itemID))
            delegate?.showDeletionAlert(object: itemObject)
        }
    }

    private func showItem(id: ObjectID) {
        guard let item = viewModel.object(with: id) else {
            HUD.showFailed()
            return
        }

        switch item.type {
        case .note:
            showNotePreview(item)
        case .link:
            openLink(item)
        default:
            showQuickLook(item)
        }
    }

    private func showQuickLook(_ item: Item) {
        do {
            let fileURL = try viewModel.temporaryFileURL(of: item)

            guard QLPreviewController.canPreview(fileURL as QLPreviewItem) else {
                HUD.showFailed(Constant.Message.unsupportedFileTypeForPreview)
                return
            }

            self.previewingItem = PreviewItem(
                objectID: item.objectID,
                previewItemURL: fileURL,
                previewItemTitle: item.name)
        } catch let error as ItemListError {
            HUD.showFailed(error.message)
        } catch {
            print("#\(#function): Failed to create temporary file for preview, \(error)")
        }

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
        do {
            let url = try viewModel.linkURL(of: item)
            let safariController = SFSafariViewController(url: url)
            safariController.preferredControlTintColor = .tintColor
            safariController.dismissButtonStyle = .close
            present(safariController, animated: true)
        } catch let error as ItemListError {
            HUD.showFailed(error.message)
        } catch {
            print("#\(#function): Failed to create temporary file for preview, \(error)")
        }
    }

    private func calculateTopContentOffset() {
        guard topContentOffset != nil else { return }
        let statusBarHeight = view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        let navBarHeight = navigationController?.navigationBar.frame.height ?? 0
        let safeAreaHeight = statusBarHeight + navBarHeight
        topContentOffset = CGPoint(x: 0, y: -safeAreaHeight)
    }
}

// MARK: - ImportMethodHandling

extension ItemListViewController: ImportMethodHandling,
    UIDocumentPickerDelegate,
    PHPickerViewControllerDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate {
    func didSelectImportMethod(_ method: ImportMethod) {
        switch method {
        case .paste:
            paste(UIPasteboard.general.itemProviders)
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

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        didPickDocument(controller, urls: urls)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        didPickMedia(picker, info: info)
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
