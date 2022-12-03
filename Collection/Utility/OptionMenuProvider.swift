//
//  OptionMenuProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/2.
//

import Combine
import UIKit

final class OptionMenuProvider {
    // MARK: - Publishers

    @Published private(set) var currentLayout: ItemLayout = .smallCard
    @Published private(set) var currentSort: ItemSort = .creationDate(ascending: false)
    @Published private(set) var currentFilterType: DisplayType?
    @Published private(set) var currentMenu: UIMenu?

    // MARK: - Properties

    private var children: [UIMenu] { [layoutMenu, sortMenu, filterMenu] }
    private let baseChildMenu = UIMenu(options: [.displayInline, .singleSelection])

    private var layoutMenu: UIMenu { baseChildMenu.replacingChildren(layoutItems) }
    private var layoutItems: [UIAction] {
        let items = ItemLayout.allCases.map { layout in
            UIAction(
                title: layout.title,
                image: layout.buttonIcon
            ) { [unowned self] _ in
                didSelectLayout(layout)
            }
        }
        items[currentLayout.rawValue].state = .on
        return items
    }

    private var sortMenu: UIMenu { baseChildMenu.replacingChildren(sortItems) }
    private var sortItems: [UIAction] {
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
        return items
    }

    private var filterMenu: UIMenu { baseChildMenu.replacingChildren(filterItems) }
    private var filterItems: [UIAction] {
        let items = DisplayType.allCases.map { type in
            let action = UIAction(
                title: type.title,
                image: type.icon?.withConfiguration(UIImage.SymbolConfiguration.unspecified)
            ) { [unowned self] _ in
                didSelectFilter(type)
            }
            action.state = .off
            return action
        }
        if let selected = currentFilterType?.rawValue {
            items[Int(selected)].state = .on
        }
        return items
    }

    // MARK: - Lifecycle

    init() {
        currentMenu = UIMenu(children: children)
    }

    // MARK: - Private

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
        currentMenu = updatedMenu()
    }

    private func didSelectFilter(_ type: DisplayType) {
        currentFilterType = type == currentFilterType ? nil : type
        currentMenu = updatedMenu()
    }

    private func updatedMenu() -> UIMenu? {
        currentMenu?.replacingChildren(children)
    }
}
