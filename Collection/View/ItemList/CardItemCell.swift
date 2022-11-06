//
//  CardItemCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import QuickLookThumbnailing
import UIKit

class CardItemCell: UICollectionViewCell {

    @IBOutlet var placeholderImageView: UIImageView!
    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var nameLabel: UILabel!

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        thumbnailImageView.image = nil
        placeholderImageView.isHidden = false
    }

    // MARK: - Methods

    func layoutItem(_ item: Item) {
        nameLabel.text = item.name
        if let thumbnail = item.thumbnail?.data {
            thumbnailImageView.image = UIImage(data: thumbnail)
            placeholderImageView.isHidden = true
        }
    }
}
