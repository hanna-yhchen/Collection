//
//  PreviewItem.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/14.
//

import Foundation
import QuickLook

class PreviewItem: NSObject, QLPreviewItem {
    var previewItemURL: URL?
    var previewItemTitle: String?
    let objectID: ObjectID

    init(objectID: ObjectID, previewItemURL: URL?, previewItemTitle: String?) {
        self.objectID = objectID
        self.previewItemURL = previewItemURL
        self.previewItemTitle = previewItemTitle ?? .empty
    }
}
