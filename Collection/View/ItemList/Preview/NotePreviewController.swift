//
//  NotePreviewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/9.
//

import UIKit

class NotePreviewController: UIViewController {

    private let item: Item
    private let itemManager: ItemManager

    @IBOutlet var noteLabel: UILabel!

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        configureContent()
    }

    init?(coder: NSCoder, item: Item, itemManager: ItemManager) {
        self.item = item
        self.itemManager = itemManager

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func configureContent() {
        title = item.name
        noteLabel.text = item.note
    }

    // MARK: - Actions

    @IBAction func editButtonTapped() {
        let editorVC = UIStoryboard.main
            .instantiateViewController(identifier: NoteEditorViewController.storyboardID) { coder in
                let viewModel = NoteEditorViewModel(itemManager: self.itemManager, scenario: .update(item: self.item))
                return NoteEditorViewController(coder: coder, viewModel: viewModel)
            }
        present(editorVC, animated: true)
    }
}
