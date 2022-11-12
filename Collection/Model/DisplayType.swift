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
            return UIImage(systemName: "play.circle")
        case .audio:
            return UIImage(systemName: "waveform")
        case .note:
            return nil
        case .link:
            return UIImage(systemName: "link")
        case .file:
            return UIImage(systemName: "doc")
        }
    }
}
