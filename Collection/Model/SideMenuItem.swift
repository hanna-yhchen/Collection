//
//  SideMenuItem.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/27.
//

import UIKit

enum SideMenuDestination {
    case itemList(ItemListViewController.Scope)
    case boardList
    case tagList
}

class SideMenuItem: Hashable {

    let title: String?
    let destination: SideMenuDestination?
    let icon: UIImage?
    let tintColor: UIColor?
    let isSubitem: Bool
    var subitems: [SideMenuItem]

    private let identifier = UUID()

    init(
        title: String?,
        destination: SideMenuDestination? = nil,
        icon: UIImage? = nil,
        tintColor: UIColor? = nil,
        isSubitem: Bool = false,
        subitems: [SideMenuItem] = []
    ) {
        self.title = title
        self.destination = destination
        self.icon = icon
        self.tintColor = tintColor
        self.isSubitem = isSubitem
        self.subitems = subitems
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    static func == (lhs: SideMenuItem, rhs: SideMenuItem) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}
