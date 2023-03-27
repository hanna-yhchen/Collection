//
//  ItemSort.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/1.
//

import UIKit

enum ItemSort {
    case creationDate(ascending: Bool)
    case updateDate(ascending: Bool)

    // MARK: - Properties

    var title: String {
        switch self {
        case .creationDate:
            return Strings.ItemList.Sort.creationDate
        case .updateDate:
            return Strings.ItemList.Sort.updateDate
        }
    }

    var sortDescriptor: NSSortDescriptor {
        switch self {
        case .creationDate(let ascending):
            return NSSortDescriptor(keyPath: \Item.creationDate, ascending: ascending)
        case .updateDate(let ascending):
            return NSSortDescriptor(keyPath: \Item.updateDate, ascending: ascending)
        }
    }

    var icon: UIImage? {
        switch self {
        case .creationDate(let ascending):
            return UIImage(systemName: ascending ? "arrow.up" : "arrow.down")
        case .updateDate(let ascending):
            return UIImage(systemName: ascending ? "arrow.up" : "arrow.down")
        }
    }

    var menuIndex: Int {
        switch self {
        case .creationDate:
            return 0
        case .updateDate:
            return 1
        }
    }

    var toggled: ItemSort {
        switch self {
        case .creationDate(let ascending):
            return .creationDate(ascending: !ascending)
        case .updateDate(let ascending):
            return .updateDate(ascending: !ascending)
        }
    }

    // MARK: - Methods

    func hasSameTypeOf(_ sort: ItemSort) -> Bool {
        switch self {
        case .creationDate:
            switch sort {
            case .creationDate:
                return true
            case .updateDate:
                return false
            }
        case .updateDate:
            switch sort {
            case .creationDate:
                return false
            case .updateDate:
                return true
            }
        }
    }
}
