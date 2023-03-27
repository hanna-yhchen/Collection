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
            return Strings.Common.rename
        case .tags:
            return Strings.Common.tags
        case .move:
            return Strings.Common.move
        case .copy:
            return Strings.Common.copy
        case .delete:
            return Strings.Common.delete
        }
    }
}
