//
//  GridCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/15.
//

import Combine
import UIKit

class GridCell: UICollectionViewCell, ItemCell {

    var viewForZooming: UIView? { thumbnailImageView }

    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var noteStackView: UIStackView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var noteLabel: UILabel!

    private var richLinkSubscription: AnyCancellable?

    override func awakeFromNib() {
        super.awakeFromNib()

        reset()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    func configure(for item: Item) {
        iconImageView.image = item.type.icon
        if let name = item.name {
            titleLabel.text = "\(name)"
            titleLabel.isHidden = false
        }
        if let filenameExtension = item.filenameExtension {
            noteLabel.text = filenameExtension
        }

        switch item.type {
        case .link:
            configureLinkPreview(for: item)
            return
        case .note:
            if let note = item.note, !note.isEmpty {
                noteLabel.text = note
            } else {
                noteLabel.text = "(empty)\n"
            }
            iconImageView.image = nil
        default:
            break
        }

        if let thumbnail = item.thumbnail?.data, let thumbnailImage = UIImage(data: thumbnail) {
            thumbnailImageView.image = thumbnailImage
            titleLabel.isHidden = true
            noteLabel.text = nil
            if item.type != .video {
                iconImageView.image = nil
            }
        }
    }

    private func configureLinkPreview(for item: Item) {
        guard
            let data = item.itemData?.data,
            let url = URL(dataRepresentation: data, relativeTo: nil)
        else { return }

        richLinkSubscription = RichLinkProvider.shared.fetchMetadata(for: url)
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<RichLinkProvider.RichLink> in
                print("#\(#function): Failed to fetch, \(error)")
                return Just((nil, url.absoluteString, nil))
            }
            .sink {[weak self] richLink in
                guard let `self` = self else { return }

                if let thumbnail = richLink.image {
                    self.thumbnailImageView.image = thumbnail
                    self.iconImageView.image = nil
                    self.titleLabel.isHidden = true
                } else {
                    self.titleLabel.isHidden = false

                    if let name = item.name, !name.isEmpty {
                        self.titleLabel.text = name
                    } else {
                        self.titleLabel.text = richLink.title
                    }
                }
            }
    }

    private func reset() {
        richLinkSubscription?.cancel()

        iconImageView.image = nil
        iconImageView.tintColor = .secondaryLabel

        thumbnailImageView.image = nil

        noteLabel.text = nil

        titleLabel.text = nil
        titleLabel.isHidden = true
    }
}
