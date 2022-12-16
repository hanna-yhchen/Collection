//
//  ContextMenuActionSendable.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/28.
//

import Combine
import UIKit

protocol ContextMenuActionSendable<MenuAction>: AnyObject {
    associatedtype MenuAction: TitleProvidable, CaseIterable

    var objectID: ObjectID? { get set }
    var subscriptions: Set<AnyCancellable> { get set }
    var actionSubject: PassthroughSubject<(MenuAction, ObjectID), Never> { get set }
    var actionPublisher: AnyPublisher<(MenuAction, ObjectID), Never> { get }
    func sendAction(_ itemAction: MenuAction)
}

extension ContextMenuActionSendable {
    var actionPublisher: AnyPublisher<(MenuAction, ObjectID), Never> {
        actionSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func sendAction(_ itemAction: MenuAction) {
        if let objectID = objectID {
            actionSubject.send((itemAction, objectID))
        }
    }

    func addContextMenu(for button: UIButton) {
        let children = MenuAction.allCases.map { menuItem in
            let action = UIAction(title: menuItem.title) { [unowned self] _ in
                sendAction(menuItem)
            }

            if menuItem.title == "Delete" {
                action.attributes = .destructive
            }
            return action
        }

        button.menu = UIMenu(children: children)
        button.showsMenuAsPrimaryAction = true
    }
}

protocol TitleProvidable: RawRepresentable {
    var title: String { get }
}

@available(iOS, deprecated: 16.0.0, message: "Use generic ContextMenuActionSendable only")
protocol ItemActionSendable: ContextMenuActionSendable<ItemAction> {}
