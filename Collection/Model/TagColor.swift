//
//  TagColor.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/18.
//

import UIKit

enum TagColor: Int16 {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case gray

    var color: UIColor {
        switch self {
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .teal:
            return .systemTeal
        case .blue:
            return .systemBlue
        case .indigo:
            return .systemIndigo
        case .gray:
            return .systemGray
        }
    }
}
