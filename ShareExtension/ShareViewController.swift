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
import UIKit
import Social

enum ShareExtensionError: Error {
    case unfoundDefaultBoard
    case failedToRetrieveAttachments
}

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        guard let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?.first?.attachments else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.failedToRetrieveAttachments)
            return
        }

        Task {
            do {
                try await ItemManager.shared.process(attachments, isSecurityScoped: false)
            } catch {
                print("#\(#function): Failed to process attachments: \(error)")
            }

            await MainActor.run {
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }
}
