//
//  ImportMethod.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/13.
//

import UIKit

enum ImportMethod: Int, CaseIterable {
    case paste
    case photos
    case camera
    case files
    case note
    case audioRecorder

    var title: String {
        switch self {
        case .paste:
            return Strings.ItemImport.Method.paste
        case .photos:
            return Strings.ItemImport.Method.photos
        case .camera:
            return Strings.ItemImport.Method.camera
        case .files:
            return Strings.ItemImport.Method.files
        case .note:
            return Strings.ItemImport.Method.note
        case .audioRecorder:
            return Strings.ItemImport.Method.audioRecorder
        }
    }

    var icon: UIImage? {
        switch self {
        case .paste:
            return UIImage(systemName: "doc.on.clipboard")
        case .photos:
            return UIImage(systemName: "photo.on.rectangle.angled")
        case .camera:
            return UIImage(systemName: "camera")
        case .files:
            return UIImage(systemName: "doc.badge.plus")
        case .note:
            return UIImage(systemName: "text.cursor")
        case .audioRecorder:
            return UIImage(systemName: "waveform")
        }
    }
}
