//
//  SmallCardCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/11.
//

import Combine
import UIKit

class SmallCardCell: UICollectionViewCell, ItemCell, ItemActionSendable {
    static let bottomAreaHeight: CGFloat = 4 + 17 + 14 + 2 + 18 + 4

    var viewForZooming: UIView? { thumbnailImageView }

    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var fileTypeLabel: UILabel!
    @IBOutlet var noteStackView: UIStackView!
    @IBOutlet var noteLabel: UILabel!
    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var titleStackView: UIStackView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var hostLabel: UILabel!
    @IBOutlet var tagStackView: UIStackView!
    @IBOutlet var actionButton: UIButton!

    var objectID: ObjectID?

    lazy var actionSubject = PassthroughSubject<(ItemAction, ObjectID), Never>()
    lazy var subscriptions = CancellableSet()

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        reset()
        addContextMenu(for: actionButton)
        self.layer.cornerRadius = 10
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    // MARK: - Methods

    func configure(for item: Item) { // swiftlint:disable:this cyclomatic_complexity
        objectID = item.objectID

        if let name = item.name, !name.isEmpty {
            titleLabel.text = name
            titleStackView.isHidden = false
        }

        iconImageView.image = item.type.icon

        if let tags = item.tags, let sortedTags = tags.sortedArray(
            using: [NSSortDescriptor(keyPath: \Tag.sortOrder, ascending: true)]
        ) as? [Tag] {
            configureTagViews(tags: sortedTags)
        }

        switch item.type {
        case .image:
            if let thumbnail = item.thumbnail?.data, let thumbnailImage = UIImage(data: thumbnail) {
                thumbnailImageView.image = thumbnailImage
                iconImageView.image = nil
            }
        case .video:
            if let thumbnail = item.thumbnail?.data, let thumbnailImage = UIImage(data: thumbnail) {
                thumbnailImageView.image = thumbnailImage
            }
        case .audio:
            break
        case .note:
            if let note = item.note, !note.isEmpty {
                noteLabel.text = note
            } else {
                noteLabel.text = "(empty)"
            }
            noteStackView.isHidden = false
            iconImageView.image = nil
        case .link:
            configureLinkPreview(for: item)
        case .file:
            if let thumbnail = item.thumbnail?.data, let thumbnailImage = UIImage(data: thumbnail) {
                thumbnailImageView.image = thumbnailImage
                iconImageView.image = nil
            } else {
                fileTypeLabel.isHidden = false
                fileTypeLabel.text = item.filenameExtension
            }
        }
    }

    func configureLinkPreview(for item: Item) {
        guard
            let data = item.itemData?.data,
            let url = URL(dataRepresentation: data, relativeTo: nil)
        else { return }

        RichLinkProvider.shared.fetchMetadata(for: url)
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<RichLinkProvider.RichLink> in
                print("#\(#function): Failed to fetch, \(error)")
                return Just((nil, url.absoluteString, nil))
            }
            .sink {[weak self] richLink in
                guard let `self` = self else { return }

                self.titleStackView.isHidden = false
                if let name = item.name, !name.isEmpty {
                    self.titleLabel.text = name
                } else {
                    self.titleLabel.text = richLink.title
                }
                self.hostLabel.text = richLink.host
                self.hostLabel.isHidden = false
                if let thumbnail = richLink.image {
                    self.thumbnailImageView.image = thumbnail
                    self.iconImageView.image = nil
                }
            }
            .store(in: &subscriptions)
    }

    private func configureTagViews(tags: [Tag]) {
        tags.forEach { tag in
            guard let color = TagColor(rawValue: tag.color)?.color else { return }

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
        subscriptions.removeAll()

        iconImageView.image = nil
        iconImageView.tintColor = .secondaryLabel

        fileTypeLabel.isHidden = true

        thumbnailImageView.image = nil

        titleStackView.isHidden = true
        titleLabel.text = nil
        hostLabel.isHidden = true
        hostLabel.text = nil

        noteStackView.isHidden = true
        noteLabel.text = nil

        tagStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
}
