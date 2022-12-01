//
//  TagEditorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/18.
//

import Combine
import UIKit

class TagEditorViewController: UIViewController {

    @IBOutlet var saveButton: UIButton!
    @IBOutlet var nameTextField: UITextField!
    @IBOutlet var colorTagButtons: [UIButton]!
    @IBOutlet var titleLabel: UILabel!

    private let viewModel: TagEditorViewModel

    @Published var selectedColorIndex = 0 {
        didSet {
            colorTagButtons[oldValue].setImage(UIImage(systemName: "tag"), for: .normal)
            colorTagButtons[selectedColorIndex].setImage(UIImage(systemName: "tag.fill"), for: .normal)
        }
    }

    private lazy var subscriptions = CancellableSet()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        addBindings()
    }

    init?(coder: NSCoder, viewModel: TagEditorViewModel) {
        self.viewModel = viewModel
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func configureHierarchy() {
        colorTagButtons.sort { $0.tag < $1.tag }
        saveButton.isEnabled = false
        titleLabel.text = viewModel.scenario.title
        nameTextField.text = viewModel.scenario.tagName
        selectedColorIndex = viewModel.scenario.tagColorIndex ?? 0
    }

    private func addBindings() {
        nameTextField.textPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.tagName, on: viewModel)
            .store(in: &subscriptions)
        $selectedColorIndex
            .receive(on: DispatchQueue.main)
            .assign(to: \.selectedColorIndex, on: viewModel)
            .store(in: &subscriptions)
        viewModel.canSave
            .receive(on: DispatchQueue.main)
            .sink {[unowned self] canSave in
                saveButton.isEnabled = canSave
            }
            .store(in: &subscriptions)
    }

    // MARK: - Actions

    @IBAction func colorTagButtonTapped(_ sender: UIButton) {
        selectedColorIndex = sender.tag
    }

    @IBAction func saveButtonTapped() {
        Task {
            do {
                try await viewModel.save()
            } catch {
                HUD.showFailed()
            }
            await MainActor.run {
                HUD.showSucceeded()
                _ = navigationController?.popViewController(animated: true)
            }
        }
    }

    @IBAction func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
}
