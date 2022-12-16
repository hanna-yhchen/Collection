//
//  OptionMenuProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/2.
//

import Combine
import CoreData
import UIKit

final class OptionMenuProvider: NSObject {
    // MARK: - Publishers

    @Published private(set) var currentLayout: ItemLayout = .initialLayout
    @Published private(set) var currentSort: ItemSort = .creationDate(ascending: false)
    @Published private(set) var currentMenu: UIMenu?

    @Published private var selectedType: DisplayType?
    @Published private var selectedTagIDs: [ObjectID] = []

    private(set) lazy var currentFilter = Publishers
        .CombineLatest($selectedType, $selectedTagIDs)
        .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
        .eraseToAnyPublisher()

    // MARK: - Properties

    private var children: [UIMenuElement] {
        var menus: [UIMenuElement] = [layoutMenu, sortMenu, typeMenu]
        if let tagMenu = tagMenu {
            menus.append(tagMenu)
        }
        menus.append(resetItem)
        return menus
    }
    private let baseChildMenu = UIMenu(options: [.displayInline, .singleSelection])

    private var layoutMenu: UIMenu {
        let items = ItemLayout.allCases.map { layout in
            UIAction(
                title: layout.title,
                image: layout.buttonIcon
            ) { [unowned self] _ in
                didSelectLayout(layout)
            }
        }
        items[currentLayout.rawValue].state = .on
        return baseChildMenu.replacingChildren(items)
    }

    private var sortMenu: UIMenu {
        var itemSorts: [ItemSort]
        switch currentSort {
        case .creationDate(let ascending):
            itemSorts = [.creationDate(ascending: ascending), .updateDate(ascending: false)]
        case .updateDate(let ascending):
            itemSorts = [.creationDate(ascending: false), .updateDate(ascending: ascending)]
        }

        let items = itemSorts.map { sort in
            UIAction(
                title: sort.title
            ) { [unowned self] _ in
                didSelectSort(sort)
            }
        }
        items[currentSort.menuIndex].image = currentSort.icon
        items[currentSort.menuIndex].state = .on

        return baseChildMenu.replacingChildren(items)
    }

    private var typeMenu: UIMenu { UIMenu(title: "Types", options: [.singleSelection], children: typeItems) }
    private var typeItems: [UIAction] {
        let items = DisplayType.allCases.map { type in
            let action = UIAction(
                title: type.title,
                image: type.icon?.withConfiguration(UIImage.SymbolConfiguration.unspecified)
            ) { [unowned self] _ in
                didSelectFilter(type)
            }
            return action
        }
        if let selected = selectedType?.rawValue {
            items[Int(selected)].state = .on
        }
        return items
    }

    private var tagMenu: UIMenu? {
        guard let tags = tagFetcher?.fetchedObjects as? [Tag] else { return nil }

        let tagItems = tags.map { (tag: Tag) in
            let tintColor = TagColor(rawValue: tag.color)?.color ?? .label
            let action = UIAction(
                title: tag.name ?? "",
                image: UIImage(systemName: "tag.fill")?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
            ) { [unowned self] _ in
                didSelectTagID(tag.objectID)
            }
            action.state = selectedTagIDs.contains(tag.objectID) ? .on : .off
            return action
        }

        return UIMenu(title: "Tags", children: tagItems)
    }

    private lazy var resetItem = UIAction(title: "Reset filters", discoverabilityTitle: "") { [unowned self] _ in
        selectedTagIDs = []
        selectedType = nil
        updateMenu()
    }

    private let storageProvider: StorageProvider?
    private var tagFetcher: NSFetchedResultsController<Tag>?

    private var cancellable: AnyCancellable?

    // MARK: - Lifecycle

    init(boardID: ObjectID? = nil, storageProvider: StorageProvider? = nil) {
        self.storageProvider = storageProvider
        super.init()

        if let boardID = boardID {
            configureTagFetcher(boardID: boardID)
        }
        updateMenu()
        addObserver()
    }

    // MARK: - Private

    private func updateMenu() {
        currentMenu = UIMenu(children: children)
    }

    private func didSelectLayout(_ layout: ItemLayout) {
        guard layout != currentLayout else { return }
        currentLayout = layout
    }

    private func didSelectSort(_ sort: ItemSort) {
        if sort.hasSameTypeOf(currentSort) {
            currentSort = sort.toggled
        } else {
            currentSort = sort
        }
        updateMenu()
    }

    private func didSelectFilter(_ type: DisplayType) {
        selectedType = type == selectedType ? nil : type
        updateMenu()
    }

    private func didSelectTagID(_ tagID: ObjectID) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.removeAll { $0 == tagID }
        } else {
            selectedTagIDs.append(tagID)
        }
        updateMenu()
    }

    private func configureTagFetcher(boardID: ObjectID) {
        guard let storageProvider = storageProvider else { return }

        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(Tag.board), boardID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.sortOrder, ascending: true)]
        fetchRequest.shouldRefreshRefetchedObjects = true

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: storageProvider.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        controller.delegate = self

        tagFetcher = controller
        try? tagFetcher?.performFetch()
    }

    private func addObserver() {
        cancellable = NotificationCenter.default.publisher(for: .tagObjectDidChange, object: storageProvider)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                try? self.tagFetcher?.performFetch()
            }
    }
}

extension OptionMenuProvider: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateMenu()
    }
}
