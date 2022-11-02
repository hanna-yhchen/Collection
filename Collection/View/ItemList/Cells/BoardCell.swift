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

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        setInitialLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        setInitialLayout()
    }

    // MARK: - Actions

    @IBAction func shareButtonTapped() {
    }

    // MARK: - Methods

    func layoutBoard(_ board: Board) {
        boardNameLabel.text = board.name
        itemCountLabel.text = "\(board.itemCount) items"

        Task {
            ownerNameLabel.text = await board.fetchOwnerName()
        }
    }

    private func setInitialLayout() {
        boardNameLabel.text = ""
        itemCountLabel.text = ""
        ownerNameLabel.text = ""
    }
}
