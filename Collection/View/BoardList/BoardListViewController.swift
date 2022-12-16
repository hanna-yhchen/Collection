//
//  BoardListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import CloudKit
import CoreData
import UIKit

protocol BoardListViewControllerDelegate: AnyObject {
    func navigateToItemList(boardID: ObjectID)
    func showNameEditorViewController(boardID: ObjectID)
    func showDeletionAlert(object: ManagedObject)
}

class BoardListViewController: UIViewController, PlaceholderViewDisplayable {

    @IBOutlet var collectionView: UICollectionView!
    var placeholderView: HintPlaceholderView?

    var isShowingPlaceholder = false

    private let viewModel: BoardListViewModel
    private weak var delegate: BoardListViewControllerDelegate?

    private lazy var subscriptions = CancellableSet()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        addBindings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        viewModel.performFetch()
    }

    init?(
        coder: NSCoder,
        viewModel: BoardListViewModel,
        delegate: BoardListViewControllerDelegate
    ) {
        self.viewModel = viewModel
        self.delegate = delegate

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

        alert.addAction(UIAlertAction(title: "Create", style: .default) { [unowned self] _ in
            HUD.show()

            guard
                let textField = alert.textFields?[0],
                let name = textField.text
            else {
                HUD.showFailed()
                return
            }

            guard !name.isEmpty, name != "Inbox" else {
                HUD.showFailed("Invalid name")
                return
            }

            do {
                try viewModel.addBoard(name: name)
                HUD.showSucceeded()
            } catch {
                HUD.showFailed()
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    // MARK: - Private Methods

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
    }

    private func configureHierarchy() {
        title = "Boards"
        navigationController?.navigationBar.prefersLargeTitles = true

        collectionView.collectionViewLayout = createCardLayout()
        collectionView.allowsSelection = true
        collectionView.delegate = self

        let cellRegistration = UICollectionView.CellRegistration<BoardCell, NSManagedObjectID>(
            cellNib: UINib(nibName: BoardCell.identifier, bundle: nil)
        ) { [unowned self] cell, _, objectID in
            guard let board = viewModel.object(with: objectID) else {
                fatalError("#\(#function): Failed to retrieve item by objectID")
            }

            cell.configure(for: board)

            cell.actionPublisher
                .sink { [unowned self] boardAction, boardID in
                    perform(boardAction, boardID: boardID)
                }
                .store(in: &cell.subscriptions)
        }

        viewModel.configureDataSource(for: collectionView) { collectionView, indexPath, board in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: board.objectID)
        }
    }

    private func perform(_ action: BoardAction, boardID: ObjectID) {
        switch action {
        case .rename:
            delegate?.showNameEditorViewController(boardID: boardID)
        case .share:
            startSharingFlow(boardID: boardID)
        case .delete:
            let boardObject = ManagedObject(entity: .board(boardID))
            delegate?.showDeletionAlert(object: boardObject)
        }
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

    private func startSharingFlow(boardID: ObjectID) {
        HUD.showProcessing()

        Task {
            do {
                let share = try await viewModel.ckShare(boardID: boardID)

                await MainActor.run {
                    let sharingController = UICloudSharingController(
                        share: share,
                        container: StorageProvider.shared.cloudKitContainer)
                    sharingController.modalPresentationStyle = .formSheet
                    present(sharingController, animated: true) {
                        HUD.dismiss()
                    }
                }
            } catch {
                print("#\(#function): Failed to get CKShare object, \(error)")
                await MainActor.run {
                    HUD.showFailed()
                }
            }
        }
    }
}

// MARK: - UICollectionViewDelegate

extension BoardListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let boardID = viewModel.objectID(for: indexPath) else { return }
        delegate?.navigateToItemList(boardID: boardID)
    }
}
