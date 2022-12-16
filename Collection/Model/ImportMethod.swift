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
            return "Paste"
        case .photos:
            return "Photo Library"
        case .camera:
            return "Camera"
        case .files:
            return "Files"
        case .note:
            return "Note"
        case .audioRecorder:
            return "Voice"
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
