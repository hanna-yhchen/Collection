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

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
    }

    override func layoutSubviews() {
        super.layoutSubviews()

//        iconImageView.layer.cornerRadius = bounds.width / 2
    }

    func configure(for method: ItemImportController.ImportMethod) {
        iconImageView.image = method.icon
        titleLabel.text = method.title
    }
}
