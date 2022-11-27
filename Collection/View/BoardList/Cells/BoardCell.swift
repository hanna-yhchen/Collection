//
//  BoardCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import UIKit

class BoardCell: UICollectionViewCell {

    @IBOutlet var boardNameLabel: UILabel!
    @IBOutlet var itemCountLabel: UILabel!
    @IBOutlet var ownerNameLabel: UILabel!
    @IBOutlet var actionButton: UIButton!

    var shareHandler: (() -> Void)?

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        self.layer.cornerRadius = 10
        setInitialLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        setInitialLayout()
    }

    // MARK: - Actions

    @IBAction func shareButtonTapped() {
        shareHandler?()
    }

    // MARK: - Methods

    func layoutBoard(_ board: Board) {
        boardNameLabel.text = board.name
        itemCountLabel.text = "\(board.itemCount) items"

        var shareInfo = ""
        if board.isPrivate && board.shareRecord == nil {
            shareInfo = "Private"
        } else if board.isOwnedByCurrentUser {
            shareInfo = "Shared"
        } else {
            shareInfo = "Shared by \(board.ownerName)"
        }
        ownerNameLabel.text = shareInfo
    }

    private func setInitialLayout() {
        boardNameLabel.text = ""
        itemCountLabel.text = ""
        ownerNameLabel.text = ""
    }
}
