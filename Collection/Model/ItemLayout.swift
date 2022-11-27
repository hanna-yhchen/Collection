//
//  ItemLayout.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/15.
//

import UIKit

enum ItemLayout: Int, CaseIterable {
    case largeCard
    case smallCard
    case grid

    var sectionInsets: UIEdgeInsets {
        switch self {
        case .largeCard:
            return UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        case .smallCard:
            return UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        case .grid:
            return UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .largeCard:
            return 16
        case .smallCard:
            return 16
        case .grid:
            return 1
        }
    }

    var cellIdentifier: String {
        switch self {
        case .largeCard:
            return LargeCardCell.identifier
        case .smallCard:
            return SmallCardCell.identifier
        case .grid:
            return GridCell.identifier
        }
    }

    var title: String {
        switch self {
        case .largeCard:
            return "Details"
        case .smallCard:
            return "Summary"
        case .grid:
            return "Grid"
        }
    }

    var buttonIcon: UIImage? {
        switch self {
        case .largeCard:
            return UIImage(systemName: "square.fill.text.grid.1x2")
        case .smallCard:
            return UIImage(systemName: "list.bullet.below.rectangle")
        case .grid:
            return UIImage(systemName: "square.grid.2x2")
        }
    }

    var next: ItemLayout {
        switch self {
        case .largeCard:
            return .smallCard
        case .smallCard:
            return .grid
        case .grid:
            return .largeCard
        }
    }

    func flowLayout() -> UICollectionViewFlowLayout {
        let flowLayout = UICollectionViewFlowLayout()

        flowLayout.minimumLineSpacing = spacing
        flowLayout.minimumInteritemSpacing = spacing
        flowLayout.sectionInset = sectionInsets

        return flowLayout
    }
}
