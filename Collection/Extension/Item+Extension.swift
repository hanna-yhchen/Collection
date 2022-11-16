//
//  Item+Extension.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/16.
//

import Foundation
import UniformTypeIdentifiers

extension Item {
    var filenameExtension: String? {
        switch self.type {
        case .note:
            return "NOTE"
        default:
            if let uti = self.uti {
                return UTType(uti)?.preferredFilenameExtension?.uppercased()
            }
        }
        return nil
    }

    var type: DisplayType {
        return DisplayType(rawValue: displayType) ?? .file
    }
}
