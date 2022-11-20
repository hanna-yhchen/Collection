//
//  NewTagViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/18.
//

import Combine
import UIKit

class NewTagViewController: UIViewController {

    @IBOutlet var createButton: UIButton!
    @IBOutlet var nameTextField: UITextField!
    @IBOutlet var colorTagButtons: [UIButton]!

    private var newTagName = "" {
        didSet {
            createButton.isEnabled = !newTagName.isEmpty
        }
    }

    private var selectedIndex = 0 {
        didSet {
            colorTagButtons[oldValue].setImage(UIImage(systemName: "tag"), for: .normal)
            colorTagButtons[selectedIndex].setImage(UIImage(systemName: "tag.fill"), for: .normal)
        }
    }

    private var cancellable: AnyCancellable?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        colorTagButtons.sort { $0.tag < $1.tag }
        createButton.isEnabled = false
        cancellable = nameTextField.textPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.newTagName, on: self)
    }

    // MARK: - Actions

    @IBAction func colorTagButtonTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
    }

    @IBAction func doneButtonTapped() {
        guard
            let color = TagColor(rawValue: Int16(selectedIndex)),
            !newTagName.isEmpty
        else {
            return
        }

        Task {
            do {
                try await StorageProvider.shared.addTag(name: newTagName, color: color)
            } catch {
                print("#\(#function): Failed to add new tag, \(error)")
            }

            await MainActor.run {
                _ = navigationController?.popViewController(animated: true)
            }
        }
    }

    @IBAction func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
}
