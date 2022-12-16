//
//  ItemAction.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/16.
//

import Foundation

enum ItemAction: Int, CaseIterable, TitleProvidable {
    case rename
    case tags
    case move
    case copy
    case delete

    var title: String {
        switch self {
        case .rename:
            return "Rename"
        case .tags:
            return "Tags"
        case .move:
            return "Move to"
        case .copy:
            return "Duplicate to"
        case .delete:
            return "Delete"
        }
    }
}
