//
//  TwoColumnCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/11.
//

import UIKit

class TwoColumnCell: UICollectionViewCell {

    @IBOutlet var placeholderImageView: UIImageView!
    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var noteTextView: UITextView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var tagStackView: UIStackView!

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        self.layer.cornerRadius = 10
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        nameLabel.text = ""
        thumbnailImageView.image = nil
        noteTextView.text = ""
        placeholderImageView.isHidden = true
        tagStackView.removeAllArrangedSubviews()
    }

    // MARK: - Methods

    func layoutItem(_ item: Item) {
        if let name = item.name as? NSString {
            nameLabel.text = name.deletingPathExtension
        }

        if let thumbnail = item.thumbnail?.data {
            thumbnailImageView.image = UIImage(data: thumbnail)
        } else if let note = item.note, !note.isEmpty {
            noteTextView.text = note
        } else {
            placeholderImageView.isHidden = false
        }

        configureTagViews(colors: [.systemRed, .systemCyan, .systemYellow])
    }

    private func configureTagViews(colors: [UIColor]) {
        for color in colors {
            let tagView = UIView()
            tagView.backgroundColor = color
            tagView.layer.cornerRadius = 8 / 2
            tagStackView.addArrangedSubview(tagView)

            tagView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tagView.widthAnchor.constraint(equalToConstant: 8),
                tagView.heightAnchor.constraint(equalToConstant: 8)
            ])
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tagStackView.addArrangedSubview(spacer)
    }
}

extension UIStackView {

    func removeAllArrangedSubviews() {

        let removedSubviews = arrangedSubviews.reduce([]) { (allSubviews, subview) -> [UIView] in
            self.removeArrangedSubview(subview)
            return allSubviews + [subview]
        }

        // Deactivate all constraints
        NSLayoutConstraint.deactivate(removedSubviews.flatMap({ $0.constraints }))

        // Remove the views from self
        removedSubviews.forEach({ $0.removeFromSuperview() })
    }
}
