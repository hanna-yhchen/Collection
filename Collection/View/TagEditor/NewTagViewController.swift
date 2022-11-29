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

    private let viewModel: NewTagViewModel

    private var newTagName = "" {
        didSet {
            createButton.isEnabled = !newTagName.isEmpty
        }
    }

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

        colorTagButtons.sort { $0.tag < $1.tag }
        createButton.isEnabled = false
        addBindings()
    }

    init?(coder: NSCoder, viewModel: NewTagViewModel) {
        self.viewModel = viewModel
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func addBindings() {
        nameTextField.textPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.tagName, on: viewModel)
            .store(in: &subscriptions)
        $selectedColorIndex
            .receive(on: DispatchQueue.main)
            .assign(to: \.selectedColorIndex, on: viewModel)
            .store(in: &subscriptions)
        viewModel.canCreate
            .receive(on: DispatchQueue.main)
            .sink {[unowned self] canCreate in
                createButton.isEnabled = canCreate
            }
            .store(in: &subscriptions)
    }

    // MARK: - Actions

    @IBAction func colorTagButtonTapped(_ sender: UIButton) {
        selectedColorIndex = sender.tag
    }

    @IBAction func createButtonTapped() {
        Task {
            do {
                try await viewModel.create()
            } catch {
                HUD.showFailed()
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
