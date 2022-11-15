//
//  TwoColumnCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/11.
//

import Combine
import UIKit
import UniformTypeIdentifiers

class TwoColumnCell: UICollectionViewCell, ItemCollectionViewCell {

    static let bottomAreaHeight: CGFloat = 4 + 17 + 14 + 2 + 18 + 4

    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var fileTypeLabel: UILabel!
    @IBOutlet var noteStackView: UIStackView!
    @IBOutlet var noteLabel: UILabel!
    @IBOutlet var thumbnailImageView: UIImageView!
    @IBOutlet var titleStackView: UIStackView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var hostLabel: UILabel!
    @IBOutlet var tagStackView: UIStackView!

    private var richLinkSubscription: AnyCancellable?

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        reset()
        self.layer.cornerRadius = 10
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    // MARK: - Methods

    func configure(for item: Item) { // swiftlint:disable:this cyclomatic_complexity
        if let name = item.name, !name.isEmpty {
            titleLabel.text = (name as NSString).deletingPathExtension
            titleStackView.isHidden = false
        }

        guard let displayType = DisplayType(rawValue: item.displayType) else {
            return
        }

        iconImageView.image = displayType.icon

        switch displayType {
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
            if let data = item.itemData?.data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                configureRichLink(for: url)
            } else {
                fileTypeLabel.isHidden = false
                fileTypeLabel.text = "Wrong data"
            }
        case .file:
            if let thumbnail = item.thumbnail?.data, let thumbnailImage = UIImage(data: thumbnail) {
                thumbnailImageView.image = thumbnailImage
                iconImageView.image = nil
            } else if let uti = item.uti {
                thumbnailImageView.isHidden = true
                fileTypeLabel.isHidden = false
                fileTypeLabel.text = UTType(uti)?.preferredFilenameExtension
            }
        }

        // TODO: display real tag data
        guard Bool.random() else { return }
        configureTagViews(colors: [.systemRed, .systemCyan, .systemYellow])
    }

    private func configureRichLink(for url: URL) {
        richLinkSubscription = RichLinkProvider.shared.fetchMetadata(for: url)
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<RichLinkProvider.RichLink> in
                print("#\(#function): Failed to fetch, \(error)")
                return Just((nil, url.absoluteString, nil))
            }
            .sink {[weak self] richLink in
                guard let `self` = self else { return }

                self.titleStackView.isHidden = false
                self.titleLabel.text = richLink.title
                self.hostLabel.text = richLink.host
                self.hostLabel.isHidden = false
                if let thumbnail = richLink.image {
                    self.thumbnailImageView.image = thumbnail
                    self.iconImageView.image = nil
                }
            }
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
        richLinkSubscription?.cancel()

        iconImageView.image = nil
        iconImageView.tintColor = .secondaryLabel

        fileTypeLabel.isHidden = true

        thumbnailImageView.isHidden = false
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
