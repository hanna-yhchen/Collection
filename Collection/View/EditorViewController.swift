//
//  EditorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import UIKit

class EditorViewController: UIViewController {

    enum Situation {
        case create, update

        var title: String {
            switch self {
            case .create:
                return "New note"
            case .update:
                return "Edit note"
            }
        }
    }

    let situation: Situation
    let completion: (String, String) -> Void

    @IBOutlet var titleTextField: UITextField!
    @IBOutlet var noteTextView: UITextView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    init?(coder: NSCoder, situation: Situation, completion: @escaping (String, String) -> Void) {
        self.situation = situation
        self.completion = completion

        super.init(coder: coder)

        self.title = situation.title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @IBAction func saveButtonTapped() {
        completion(titleTextField.text ?? "", noteTextView.text ?? "")
        navigationController?.popViewController(animated: true)
    }
}
