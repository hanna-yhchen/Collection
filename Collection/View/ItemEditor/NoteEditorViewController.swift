//
//  NoteEditorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import UIKit

class NoteEditorViewController: UIViewController {

    private let viewModel: NoteEditorViewModel
    private lazy var subscriptions = CancellableSet()

    @IBOutlet private var sheetTitleLabel: UILabel!
    @IBOutlet private var titleTextField: UITextField!
    @IBOutlet private var noteTextView: UITextView!
    @IBOutlet private var placeholderLabel: UILabel!
    @IBOutlet private var saveButton: UIButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        addBindings()
    }

    init?(coder: NSCoder, viewModel: NoteEditorViewModel) {
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
        sheetTitleLabel.text = viewModel.scenario.title
        placeholderLabel.isHidden = !viewModel.note.isEmpty
    }

    private func addBindings() {
        keyboardFrameSubscription
            .store(in: &subscriptions)
        titleTextField.textPublisher
            .assign(to: \.name, on: viewModel)
            .store(in: &subscriptions)
        noteTextView.textPublisher
            .assign(to: \.note, on: viewModel)
            .store(in: &subscriptions)
        noteTextView.textPublisher
            .receive(on: DispatchQueue.main)
            .sink {[unowned self] input in
                placeholderLabel.isHidden = !input.isEmpty
            }
            .store(in: &subscriptions)
        viewModel.canSave
            .receive(on: DispatchQueue.main)
            .sink {[unowned self] canSave in
                saveButton.isEnabled = canSave
            }
            .store(in: &subscriptions)
    }

    private func showUnsavedChangesAlert() {
        let alert = UIAlertController(
            title: "Unsaved Changes",
            message: "You have unsaved changes. Are you sure you want to leave this page and discard your changes?",
            preferredStyle: UIDevice.current.userInterfaceIdiom == .phone ? .actionSheet : .alert)
        alert.addAction(UIAlertAction(title: "Stay", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) {[unowned self] _ in
            dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

    @IBAction private func saveButtonTapped() {
        HUD.showProcessing()
        Task {
            do {
                try await viewModel.save()
                HUD.showSucceeded()
                dismiss(animated: true)
            } catch {
                // TODO: handle error
                print("#\(#function): Failed to save new note, \(error)")
                HUD.showFailed()
            }
        }
    }

    @IBAction private func cancelButtonTapped() {
        guard !viewModel.hasChanges else {
            showUnsavedChangesAlert()
            return
        }

        dismiss(animated: true)
    }
}

// MARK: - KeyboardHandling

extension NoteEditorViewController: KeyboardHandling {
    func keyboardWillChangeFrame(yOffset: CGFloat, duration: TimeInterval, animationCurve: UIView.AnimationOptions) {
        noteTextView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: -yOffset, right: 0)
        noteTextView.scrollIndicatorInsets = noteTextView.contentInset
        noteTextView.scrollRangeToVisible(noteTextView.selectedRange)
    }
}
