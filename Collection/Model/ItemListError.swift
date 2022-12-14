//
//  ItemListError.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/14.
//

import Foundation

enum ItemListError: Error {
    case missingFileInformation
    case failedWritingToTempFile

    var message: String {
        switch self {
        case .missingFileInformation:
            return "Missing information of the item"
        case .failedWritingToTempFile:
            return "Unable to read the file"
        }
    }
}
