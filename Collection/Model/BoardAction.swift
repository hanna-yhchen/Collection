//
//  BoardAction.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/28.
//

import Foundation

enum BoardAction: Int, CaseIterable, TitleProvidable {
    case rename
    case share
    case delete

    var title: String {
        switch self {
        case .rename:
            return Strings.Common.rename
        case .share:
            return Strings.Common.share
        case .delete:
            return Strings.Common.delete
        }
    }
}
