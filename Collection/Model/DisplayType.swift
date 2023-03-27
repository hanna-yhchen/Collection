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
            return Strings.DisplayType.Title.image
        case .video:
            return Strings.DisplayType.Title.video
        case .audio:
            return Strings.DisplayType.Title.audio
        case .note:
            return Strings.DisplayType.Title.note
        case .link:
            return Strings.DisplayType.Title.link
        case .file:
            return Strings.DisplayType.Title.file
        }
    }

    var predicate: NSPredicate {
        NSPredicate(format: "%K == %ld", #keyPath(Item.displayType), rawValue)
    }
}
