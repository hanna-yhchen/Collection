//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Hanna Chen on 2022/11/5.
//
/*
 Build files:
 StorageProvider, StorageProvider+Item, StorageHistoryManage, UserDefault, UserDefaults+Extension, Collection(Core Data Model), DateFormatter+Extensions, ThumbnailProvider, ItemManager
 */

import CoreData
import UniformTypeIdentifiers
import UIKit
import Social

enum ShareExtensionError: Error {
    case unfoundDefaultBoard
    case failedToRetrieveAttachments
}

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        processInput()
    }

    private func processInput() {
        HUD.showProcessing()

        guard var attachments = (extensionContext?.inputItems as? [NSExtensionItem])?.first?.attachments else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.failedToRetrieveAttachments)
            return
        }

        // exclude text intended for social post
        if attachments.count > 1 {
            attachments.removeAll { itemProvider in
                itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
                && !itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            }
        }

        Task {
            do {
                try await ItemManager().process(attachments, isSecurityScoped: false)
            } catch {
                print("#\(#function): Failed to process attachments: \(error)")
            }

            HUD.showSucceeded("Added to Inbox")

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }
}
