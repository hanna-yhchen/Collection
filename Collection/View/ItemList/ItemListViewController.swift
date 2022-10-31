//
//  ItemListViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/28.
//

import UniformTypeIdentifiers
import UIKit

class ItemListViewController: UIViewController {

    let storageProvider: StorageProvider

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    init?(coder: NSCoder, storageProvider: StorageProvider) {
        self.storageProvider = storageProvider

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @IBAction func addButtonTapped() {
        showDocumentPicker()
    }

    // MARK: - Private Methods

    private func showDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = self
        picker.allowsMultipleSelection = true

        present(picker, animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate

extension ItemListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        urls.forEach { url in
            guard url.startAccessingSecurityScopedResource() else { return }

            defer { url.stopAccessingSecurityScopedResource() }

            var error: NSError?

            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { url in
                guard
                    let values = try? url.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey]),
                    let size = values.fileSize,
                    size <= 20_000_000,
                    let type = values.contentType,
                    let name = values.name,
                    let data = try? Data(contentsOf: url)
                else {
                    return
                }

                storageProvider.addItem(
                    name: name,
                    contentType: type.identifier,
                    itemData: data)
            }
        }
    }
}
