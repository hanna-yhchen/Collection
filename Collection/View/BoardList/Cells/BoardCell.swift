//
//  BoardCell.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/2.
//

import Combine
import UIKit

class BoardCell: UICollectionViewCell, ContextMenuActionSendable {

    typealias MenuAction = BoardAction

    @IBOutlet var boardNameLabel: UILabel!
    @IBOutlet var itemCountLabel: UILabel!
    @IBOutlet var shareStatusLabel: UILabel!
    @IBOutlet var actionButton: UIButton!

    var objectID: ObjectID?

    lazy var actionSubject = PassthroughSubject<(MenuAction, ObjectID), Never>()
    lazy var subscriptions = CancellableSet()

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        self.layer.cornerRadius = 10
        reset()
        addContextMenu(for: actionButton)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    // MARK: - Methods

    func configure(for board: Board) {
        objectID = board.objectID

        boardNameLabel.text = board.name
        itemCountLabel.text = "\(board.itemCount) items"

        var shareStatus = ""
        // FIXME: shareRecord exists after stop sharing
        if (board.isPrivate && board.shareRecord == nil) || (board.shareRecord?.participants.count)! <= 1 {
            shareStatus = "Private"
        } else if board.isOwnedByCurrentUser {
            shareStatus = "Shared"
        } else {
            shareStatus = "Shared by \(board.ownerName)"
        }
        shareStatusLabel.text = shareStatus
    }

    private func reset() {
        subscriptions.removeAll()

        boardNameLabel.text = nil
        itemCountLabel.text = nil
        shareStatusLabel.text = nil
    }
}
