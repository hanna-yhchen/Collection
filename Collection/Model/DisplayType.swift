//
//  DisplayType.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/12.
//

import UIKit

enum DisplayType: Int16, CaseIterable {
    case image
    case video
    case audio
    case note
    case link
    case file

    var icon: UIImage? {
        switch self {
        case .image:
            return UIImage(systemName: "photo")
        case .video:
            let colorConfig = UIImage.SymbolConfiguration(
                paletteColors: [.tintColor, .tertiarySystemBackground, .tertiarySystemBackground])
            return UIImage(systemName: "play.circle.fill", withConfiguration: colorConfig)
        case .audio:
            let config = UIImage.SymbolConfiguration(pointSize: 65)
            return UIImage(systemName: "waveform.path", withConfiguration: config)
        case .note:
            return UIImage(systemName: "textformat")
        case .link:
            return UIImage(systemName: "link")
        case .file:
            return UIImage(systemName: "doc")
        }
    }

    var title: String {
        switch self {
        case .image:
            return "Image"
        case .video:
            return "Video"
        case .audio:
            return "Audio"
        case .note:
            return "Notes"
        case .link:
            return "Link"
        case .file:
            return "File"
        }
    }

    var predicate: NSPredicate {
        NSPredicate(format: "%K == %ld", #keyPath(Item.displayType), rawValue)
    }
}
