//
//  SideMenuViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/26.
//

import Combine
import CoreData
import UIKit

class SideMenuViewController: UIViewController {

    enum Section {
        case main
    }

    typealias DataSource = UICollectionViewDiffableDataSource<Section, SideMenuItem>
    typealias SectionSnapshot = NSDiffableDataSourceSectionSnapshot<SideMenuItem>

    // MARK: - Properties

    var destinationPublisher: AnyPublisher<SideMenuDestination, Never> {
        destinationSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private lazy var destinationSubject = PassthroughSubject<SideMenuDestination, Never>()
    private lazy var subscriptions = CancellableSet()

    private let storageProvider: StorageProvider

    // swiftlint:disable implicitly_unwrapped_optional
    private var dataSource: DataSource!
    private var collectionView: UICollectionView!
    // swiftlint:enable implicitly_unwrapped_optional

    private lazy var menuItems = [
        SideMenuItem(
            title: "All Items",
            destination: .itemList(.allItems),
            icon: UIImage(named: "fluid-rectangle")),
        SideMenuItem(
            title: "Inbox",
            destination: .itemList(.board(storageProvider.getInboxBoardID())),
            icon: UIImage(systemName: "tray")),
        boardMenu,
    ]

    private lazy var boardMenu = SideMenuItem(
        title: "Boards",
        destination: .boardList,
        icon: UIImage(systemName: "square.stack.3d.up"))

    private lazy var managedObjectContext = storageProvider.persistentContainer.viewContext

    private lazy var boardFetcher: NSFetchedResultsController<Board> = {
        let fetchRequest = Board.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Board.name), "Inbox")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Board.sortOrder, ascending: false)]

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: managedObjectContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        controller.delegate = self

        return controller
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureCollectionView()
        configureDataSource()
        addObservers()
        fetchBoards()
    }

    // MARK: - Initializers

    init(storageProvider: StorageProvider) {
        self.storageProvider = storageProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func configureCollectionView() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createListLayout())
        view.addSubview(collectionView)
        collectionView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        collectionView.delegate = self
        self.collectionView = collectionView
    }

    private func configureDataSource() {
        typealias CellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SideMenuItem>

        let mainCellRegistration = CellRegistration {[unowned self] cell, _, menuItem in
            var content = cell.defaultContentConfiguration()
            content.text = menuItem.title
            content.textProperties.font = .systemFont(ofSize: 24, weight: .semibold)
            content.image = menuItem.icon
            content.imageProperties.tintColor = menuItem.tintColor
            content.imageProperties.reservedLayoutSize = CGSize(width: 24, height: 24)
            content.imageProperties.preferredSymbolConfiguration = .init(pointSize: 24, weight: .medium)
            content.directionalLayoutMargins = .init(top: 16, leading: 0, bottom: 16, trailing: 0)
            content.imageToTextPadding = 24
            cell.contentConfiguration = content

            if menuItem == boardMenu {
                let disclosureOptions = UICellAccessory.OutlineDisclosureOptions(style: .cell)
                cell.accessories = [.outlineDisclosure(options: disclosureOptions)]
            }

            cell.backgroundConfiguration = .clear()
        }

        let subitemCellRegistration = CellRegistration { cell, _, menuItem in
            var content = cell.defaultContentConfiguration()
            content.text = menuItem.title
            content.textProperties.font = .systemFont(ofSize: 20, weight: .medium)
            content.directionalLayoutMargins = .init(top: 8, leading: 24, bottom: 8, trailing: 0)
            cell.contentConfiguration = content

            cell.backgroundConfiguration = .clear()
        }

        self.dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, menuItem in
            if menuItem.isSubitem {
                return collectionView.dequeueConfiguredReusableCell(
                    using: subitemCellRegistration,
                    for: indexPath,
                    item: menuItem)
            } else {
                return collectionView.dequeueConfiguredReusableCell(
                    using: mainCellRegistration,
                    for: indexPath,
                    item: menuItem)
            }
        }

        applyLatestSnapshot()
    }

    private func applyLatestSnapshot() {
        var snapshot = SectionSnapshot()

        func addItems(_ menuItems: [SideMenuItem], to parent: SideMenuItem?) {
            snapshot.append(menuItems, to: parent)
            for menuItem in menuItems where !menuItem.subitems.isEmpty {
                addItems(menuItem.subitems, to: menuItem)
            }
        }

        addItems(menuItems, to: nil)

        dataSource.apply(snapshot, to: .main, animatingDifferences: false)
    }

    private func createListLayout() -> UICollectionViewLayout {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.showsSeparators = false
        listConfiguration.backgroundColor = .clear
        return UICollectionViewCompositionalLayout.list(using: listConfiguration)
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
                    to: self.managedObjectContext)
            }
            .store(in: &subscriptions)
    }

    private func fetchBoards() {
        try? boardFetcher.performFetch()
        if let boards = boardFetcher.fetchedObjects {
            updateBoardMenu(with: boards)
        }
    }

    private func updateBoardMenu(with boards: [Board]) {
        boardMenu.subitems = boards.map { board in
            SideMenuItem(title: board.name, destination: .itemList(.board(board.objectID)), isSubitem: true)
        }

        applyLatestSnapshot()
    }
}

// MARK: - UICollectionViewDelegate

extension SideMenuViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let menuItem = self.dataSource.itemIdentifier(for: indexPath) else {
            fatalError("#\(#function): Undefined menu item")
        }

        collectionView.deselectItem(at: indexPath, animated: true)

        if let destination = menuItem.destination {
            destinationSubject.send(destination)
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension SideMenuViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let boards = controller.fetchedObjects as? [Board] {
            updateBoardMenu(with: boards)
        }
    }
}
