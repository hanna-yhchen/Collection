//
//  EditorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import UIKit

class EditorViewController: UIViewController {

    enum Situation {
        case create
        case update(Item)

        var title: String {
            switch self {
            case .create:
                return "New note"
            case .update:
                return "Edit note"
            }
        }
    }

    let viewModel: EditorViewModel
    private lazy var subscriptions = CancellableSet()

    @IBOutlet var titleTextField: UITextField!
    @IBOutlet var noteTextView: UITextView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        addBindings()
    }

    init?(coder: NSCoder, viewModel: EditorViewModel) {
        self.viewModel = viewModel

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func configureHierarchy() {
        titleTextField.text = viewModel.name
        noteTextView.text = viewModel.note
        title = viewModel.scenario.title
    }

    private func addBindings() {
        titleTextField.textPublisher
            .assign(to: \.name, on: viewModel)
            .store(in: &subscriptions)
        noteTextView.textPublisher
            .assign(to: \.note, on: viewModel)
            .store(in: &subscriptions)
    }

    // MARK: - Actions

    @IBAction func saveButtonTapped() {
        Task {
            // TODO: handle error 
            try? await viewModel.save()
            await MainActor.run {
                _ = navigationController?.popViewController(animated: true)
            }
        }
    }
}
