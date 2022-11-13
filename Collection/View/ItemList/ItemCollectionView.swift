//
//  ItemCollectionView.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/11.
//

import UIKit

class ItemCollectionView: UICollectionView {

    enum Layout {
        case detailedCard
        case conciseCard
        case grid
    }

    var traits: UITraitCollection?

    private let sectionInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    private let spacing: CGFloat = 16

    func setTwoColumnLayout(animated: Bool) {
        setCollectionViewLayout(twoColumnLayout, animated: animated)
    }

    init(frame: CGRect, traits: UITraitCollection) {
        self.traits = traits

        super.init(frame: frame, collectionViewLayout: UICollectionViewLayout())

        backgroundColor = .clear
        self.contentInset = sectionInsets
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private lazy var twoColumnLayout: UICollectionViewLayout = {
        let layout = UICollectionViewFlowLayout()

        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing
        layout.sectionInset = sectionInsets

        let itemsPerRow: CGFloat = traits?.horizontalSizeClass == .compact ? 2 : 4
        let availableWidth = bounds.width - ((itemsPerRow + 1) * spacing)
        let widthPerItem = (availableWidth / itemsPerRow).rounded(.down)
        layout.itemSize = CGSize(width: widthPerItem, height: widthPerItem + TwoColumnCell.bottomAreaHeight)

        return layout
    }()
}
