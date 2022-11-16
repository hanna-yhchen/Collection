//
//  ItemCollectionView.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/11.
//

import UIKit

protocol ItemCell: UICollectionViewCell {
    func configure(for item: Item)
}

class ItemCollectionView: UICollectionView {

    var traits: UITraitCollection?

    lazy var flowLayouts: [ItemLayout: UICollectionViewFlowLayout] = {
        var flowLayouts: [ItemLayout: UICollectionViewFlowLayout] = [:]
        ItemLayout.allCases.forEach { itemLayout in
            flowLayouts.updateValue(itemLayout.flowLayout(), forKey: itemLayout)
        }
        return flowLayouts
    }()

    // MARK: - Initializers

    init(frame: CGRect, traits: UITraitCollection) {
        self.traits = traits

        super.init(frame: frame, collectionViewLayout: UICollectionViewFlowLayout())

        backgroundColor = .systemGroupedBackground

        register(
            UINib(nibName: GridCell.identifier, bundle: nil),
            forCellWithReuseIdentifier: GridCell.identifier)
        register(
            UINib(nibName: SmallCardCell.identifier, bundle: nil),
            forCellWithReuseIdentifier: SmallCardCell.identifier)
        register(
            UINib(nibName: LargeCardCell.identifier, bundle: nil),
            forCellWithReuseIdentifier: LargeCardCell.identifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Methods

    func setLayout(_ layout: ItemLayout, animated: Bool) {
        guard let flowLayout = flowLayouts[layout] else { return }
        setCollectionViewLayout(flowLayout, animated: animated)
    }

    func itemSize(for layout: ItemLayout) -> CGSize {
        let sectionInsets = layout.sectionInsets
        var itemsPerRow: CGFloat = 1
        var heightOffset: CGFloat = 0

        switch layout {
        case .largeCard:
            itemsPerRow = 1
        case .smallCard:
            itemsPerRow = traits?.horizontalSizeClass == .compact ? 2 : 4
            heightOffset = SmallCardCell.bottomAreaHeight
        case .grid:
            itemsPerRow = traits?.horizontalSizeClass == .compact ? 3 : 5
        }

        let availableWidth = bounds.width
            - ((itemsPerRow - 1) * layout.spacing)
            - (sectionInsets.left + sectionInsets.right)
        let widthPerItem = (availableWidth / itemsPerRow).rounded(.down)

        var height = widthPerItem + heightOffset
        if layout == .largeCard {
            height = max(widthPerItem * 0.4 * 4 / 3, LargeCardCell.minHeight)
        }

        return CGSize(width: widthPerItem, height: height)
    }
}
