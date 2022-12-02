//
//  LargeCardCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/15.
//

import Combine
import TTGTags
import UIKit

class LargeCardCell: UICollectionViewCell, ItemCell, ItemActionSendable {

    static let minHeight: CGFloat = {
        let spacing: CGFloat = 4
        let components: CGFloat = 17 + 21 + 15 + 12 + 12 + 50 + 18
        return components + spacing * 8
    }()

    var viewForZooming: UIView? { thumbnailImageView }

    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var noteStackView: UIStackView!
    @IBOutlet var noteLabel: UILabel!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var creationDateLabel: UILabel!
    @IBOutlet var updateDateLabel: UILabel!
    @IBOutlet var tagContainerView: UIView!
    @IBOutlet var actionButton: UIButton!

    private var tagView: TTGTextTagCollectionView?

    var objectID: ObjectID?

    lazy var actionSubject = PassthroughSubject<(ItemAction, ObjectID), Never>()
    lazy var subscriptions = CancellableSet()

    override func awakeFromNib() {
        super.awakeFromNib()

        self.layer.cornerRadius = 10
        reset()
        addActionMenu(for: actionButton)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    func configure(for item: Item) {
        objectID = item.objectID

        iconImageView.image = item.type.icon

        if let creationDate = item.creationDate, let updateDate = item.updateDate {
            creationDateLabel.text = "Created at "
                + DateFormatter.hyphenatedDateTimeFormatter.string(from: creationDate)
            updateDateLabel.text = "Updated on "
                + DateFormatter.hyphenatedDateTimeFormatter.string(from: updateDate)
        }

        if let tags = item.tags, let sortedTags = tags.sortedArray(
            using: [NSSortDescriptor(keyPath: \Tag.sortOrder, ascending: true)]
        ) as? [Tag] {
            configureTagView(tags: sortedTags)
        }

        switch item.type {
        case .link:
            configureLinkPreview(for: item)
            return
        case .note:
            if let note = item.note, !note.isEmpty {
                noteLabel.text = note
            } else {
                noteLabel.text = "(empty)"
            }
            noteStackView.isHidden = false
            iconImageView.image = nil
        default:
            break
        }

        if let name = item.name {
            titleLabel.text = name
        } else {
            titleLabel.isHidden = true
        }
        subtitleLabel.text = item.filenameExtension

        if let thumbnail = item.thumbnail?.data, let thumbnailImage = UIImage(data: thumbnail) {
            thumbnailImageView.image = thumbnailImage
            if item.type != .video {
                iconImageView.image = nil
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

                if let name = item.name, !name.isEmpty {
                    self.titleLabel.text = name
                } else {
                    self.titleLabel.text = richLink.title
                }
                self.subtitleLabel.text = richLink.host
                if let thumbnail = richLink.image {
                    self.thumbnailImageView.image = thumbnail
                    self.iconImageView.image = nil
                }
            }
            .store(in: &subscriptions)
    }
    // TODO: use Tag object
    private func configureTagView(tags: [Tag]) {
        guard let tagView = tagView else {
            let tagView = TTGTextTagCollectionView()
            tagView.contentInset = .zero
            tagView.horizontalSpacing = 2
            tagView.verticalSpacing = 2

            tagContainerView.addSubview(tagView)
            tagView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tagView.topAnchor.constraint(equalTo: tagContainerView.topAnchor),
                tagView.leadingAnchor.constraint(equalTo: tagContainerView.leadingAnchor),
                tagView.bottomAnchor.constraint(equalTo: tagContainerView.bottomAnchor),
                tagView.trailingAnchor.constraint(equalTo: tagContainerView.trailingAnchor),
            ])

            self.tagView = tagView
            configureTagView(tags: tags)

            return
        }

        let tagStyle = TTGTextTagStyle()
        tagStyle.cornerRadius = 5
        tagStyle.borderWidth = 0
        tagStyle.shadowOpacity = 0
        tagStyle.extraSpace = CGSize(width: 8, height: 4)

        let textTags = tags.map { tag in
            tagStyle.backgroundColor = TagColor(rawValue: tag.color)?.color ?? .clear

            return TTGTextTag(
                content: TTGTextTagStringContent(
                    text: tag.name ?? "   ",
                    textFont: .systemFont(ofSize: 10),
                    textColor: .white),
                style: tagStyle)
        }

        tagView.add(textTags)
        tagView.reload()
    }

    private func reset() {
        subscriptions.removeAll()

        if let tagView = tagView {
            tagView.removeAllTags()
            tagView.reload()
        }

        titleLabel.text = nil
        titleLabel.isHidden = false
        subtitleLabel.text = nil

        thumbnailImageView.image = nil

        iconImageView.image = nil
        iconImageView.tintColor = .secondaryLabel

        noteLabel.text = nil
        noteStackView.isHidden = true
    }
}
