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
        ownerNameLabel.text = board.ownerName
    }

    private func setInitialLayout() {
        boardNameLabel.text = ""
        itemCountLabel.text = ""
        ownerNameLabel.text = ""
    }
}
