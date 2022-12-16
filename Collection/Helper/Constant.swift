//
//  Constant.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/6.
//

import Foundation

enum Constant {

    enum Message {
        static let missingData = "Missing data"
        static let unsupportedFileTypeForPreview = "Preview of this file type is not supported"
        static let deletionTitleFormat = "Delete the %@"
        static let deletionMsgFormat = "Are you sure you want to delete this %@ permanently?"
        static let delete = "Delete"
        static let deleted = "Deleted"
        static let cancel = "Cancel"
    }

    enum Layout {
        static let sheetCornerRadius: CGFloat = 30
    }
}
