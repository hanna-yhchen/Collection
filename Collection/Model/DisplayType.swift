//
//  DisplayType.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/12.
//

import UIKit

enum DisplayType: Int16 {
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
            let sizeConfig = UIImage.SymbolConfiguration(pointSize: 30)
            return UIImage(systemName: "play.circle.fill", withConfiguration: colorConfig.applying(sizeConfig))
        case .audio:
            let sizeConfig = UIImage.SymbolConfiguration(pointSize: 50)
            return UIImage(systemName: "waveform.path", withConfiguration: sizeConfig)
        case .note:
            return nil
        case .link:
            return UIImage(systemName: "link")
        case .file:
            return UIImage(systemName: "doc")
        }
    }
}
