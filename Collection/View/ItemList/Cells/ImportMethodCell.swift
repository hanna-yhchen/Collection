//
//  ImportMethodCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/14.
//

import UIKit

class ImportMethodCell: UICollectionViewCell {

    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var titleLabel: UILabel!

    func configure(for method: ImportMethod) {
        iconImageView.image = method.icon
        titleLabel.text = method.title
    }
}
