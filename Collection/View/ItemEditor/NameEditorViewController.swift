//
//  NameEditorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/17.
//

import Combine
import UIKit

class NameEditorViewController: UIViewController {

    @IBOutlet var dimmedView: UIView!
    @IBOutlet var sheetView: UIView!
    @IBOutlet var nameTextField: UITextField!
    @IBOutlet var sheetBottomConstraint: NSLayoutConstraint!

    // MARK: - Properties

    private let sheetHeight: CGFloat = 130

    private lazy var newNameSubject = PassthroughSubject<String, Never>()
    var newNamePublisher: AnyPublisher<String, Never> {
        newNameSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    var cancellable: AnyCancellable?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        animatePresentSheet()
        nameTextField.becomeFirstResponder()
    }

    // MARK: - Actions

    @IBAction func saveButtonTapped() {
        newNameSubject.send(nameTextField.text ?? "")
    }

    @IBAction func closeButtonTapped() {
        animateDismissSheet()
    }

    // MARK: - Private

    private func configureUI() {
        view.backgroundColor = .clear

        sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetView.layer.cornerRadius = 30

        sheetBottomConstraint.constant = sheetHeight
    }

    private func animatePresentSheet() {
        sheetBottomConstraint.constant = 0 + 16

        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) {
            self.dimmedView.alpha = 0.12
            self.view.layoutIfNeeded()
        }
    }

    func animateDismissSheet() {
        self.nameTextField.resignFirstResponder()

        sheetBottomConstraint.constant = sheetHeight

        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut) {
            self.dimmedView.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }
}
