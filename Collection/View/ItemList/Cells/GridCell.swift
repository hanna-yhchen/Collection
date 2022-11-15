//
//  GridCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/15.
//

import Combine
import UIKit

class GridCell: UICollectionViewCell, ItemCollectionViewCell {

    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var thumbnailImageView: UIImageView!

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
        guard let displayType = DisplayType(rawValue: item.displayType) else {
            return
        }

        iconImageView.image = displayType.icon

        if displayType == .link {
            if let data = item.itemData?.data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                configureLinkPreview(for: url)
            }
            return
        }

        if let thumbnail = item.thumbnail?.data, let thumbnailImage = UIImage(data: thumbnail) {
            thumbnailImageView.image = thumbnailImage
            if displayType != .video {
                iconImageView.image = nil
            }
        }
    }

    func configureLinkPreview(for url: URL) {
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
                }
            }
    }

    private func reset() {
        richLinkSubscription?.cancel()

        iconImageView.image = nil
        iconImageView.tintColor = .secondaryLabel

        thumbnailImageView.image = nil
    }
}
