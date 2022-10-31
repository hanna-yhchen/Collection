//
//  CardItemCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import UIKit

class CardItemCell: UICollectionViewCell {

    @IBOutlet var placeholderImageView: UIImageView!
    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var nameLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
}
