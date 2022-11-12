//
//  TwoColumnCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/11.
//

import UIKit
import UniformTypeIdentifiers

class TwoColumnCell: UICollectionViewCell {

    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var fileTypeLabel: UILabel!
    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var noteTextView: UITextView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var tagStackView: UIStackView!

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        reset()
        self.layer.cornerRadius = 10
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    // MARK: - Methods

    func configure(for item: Item) {
        nameLabel.text = item.name

        guard let displayType = DisplayType(rawValue: item.displayType) else {
            return
        }

        iconImageView.image = displayType.icon

        switch displayType {
        case .image:
            if let thumbnail = item.thumbnail?.data {
                iconImageView.image = nil
                thumbnailImageView.image = UIImage(data: thumbnail)
            }
        case .video:
            if let thumbnail = item.thumbnail?.data {
                thumbnailImageView.image = UIImage(data: thumbnail)
            }
            iconImageView.tintColor = .tintColor
            iconImageView.image = UIImage(systemName: "play.circle")
        case .audio:
            iconImageView.image = UIImage(systemName: "waveform")
        case .note:
            if let note = item.note, !note.isEmpty {
                noteTextView.text = note
            } else {
                fileTypeLabel.text = "Empty note"
            }
        case .link:
            // TODO: rich link presentation
            break
        case .file:
            if let thumbnail = item.thumbnail?.data {
                thumbnailImageView.image = UIImage(data: thumbnail)
                iconImageView.image = nil
            } else if let uti = item.uti {
                fileTypeLabel.text = UTType(uti)?.preferredFilenameExtension
            }
        }

        // TODO: display real tag data
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

    private func reset() {
        iconImageView.image = nil
        iconImageView.tintColor = .secondaryLabel
        fileTypeLabel.text = ""
        thumbnailImageView.image = nil
        nameLabel.text = ""
        noteTextView.text = ""
        tagStackView.removeAllArrangedSubviews()
    }
}

extension UIStackView {

    func removeAllArrangedSubviews() {

        arrangedSubviews.forEach { $0.removeFromSuperview() }

//        let removedSubviews = arrangedSubviews.reduce([]) { (allSubviews, subview) -> [UIView] in
//            self.removeArrangedSubview(subview)
//            return allSubviews + [subview]
//        }
//
//        // Deactivate all constraints
//        NSLayoutConstraint.deactivate(removedSubviews.flatMap({ $0.constraints }))
//
//        // Remove the views from self
//        removedSubviews.forEach({ $0.removeFromSuperview() })
    }
}
