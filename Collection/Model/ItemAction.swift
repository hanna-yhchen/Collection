//
//  ItemAction.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/16.
//

import Combine
import UIKit

protocol ItemActionSendable {
    var objectID: ObjectID? { get set }
    var subscriptions: Set<AnyCancellable> { get set }
    var actionSubject: PassthroughSubject<(ItemAction, ObjectID), Never> { get set }
    var actionPublisher: AnyPublisher<(ItemAction, ObjectID), Never> { get }
    func sendAction(_ itemAction: ItemAction)
}

extension ItemActionSendable {
    var actionPublisher: AnyPublisher<(ItemAction, ObjectID), Never> {
        actionSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func sendAction(_ itemAction: ItemAction) {
        if let objectID = objectID {
            actionSubject.send((itemAction, objectID))
        }
    }

    func addActionMenu(for button: UIButton) {
        let children = ItemAction.allCases.map { itemAction in
            let action = UIAction(title: itemAction.title) { _ in
                self.sendAction(itemAction)
            }
            if itemAction == .delete {
                action.attributes = .destructive
            }
            return action
        }

        button.menu = UIMenu(children: children)
        button.showsMenuAsPrimaryAction = true
    }
}

enum ItemAction: Int, CaseIterable {
    case rename
    case tags
//    case comments
    case move
    case copy
    case delete

    var title: String {
        switch self {
        case .rename:
            return "Rename"
        case .tags:
            return "Tags"
//        case .comments:
//            return "Comments"
        case .move:
            return "Move to"
        case .copy:
            return "Duplicate to"
        case .delete:
            return "Delete"
        }
    }
}
